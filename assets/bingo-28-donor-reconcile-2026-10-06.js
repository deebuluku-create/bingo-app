/* Bingo #28 donor reconciliation — 2026-10-06.
   Surgical runtime bridge only: Topic upload transport + media/card guards.
   No layout, data model, navigation, comments, crowns, share, or payment rewrites. */
(function(){'use strict';
if(window.__bingo28DonorReconcile)return;window.__bingo28DonorReconcile=1;

/* d55eb68: Topic media must use the standard Supabase Storage object endpoint at every size.
   Keep the same topic-media bucket/path/policy/rollback owned by the master. */
function installTopicTransport(){
 if(typeof window.aaUploadStorageWithFeedback!=='function'||window.aaUploadStorageWithFeedback.__bingoTopicStandard)return false;
 var original=window.aaUploadStorageWithFeedback;
 async function wrapped(bucket,path,file,options){
   var o=options&&typeof options==='object'?Object.assign({},options):{};
   if(String(bucket||'')==='topic-media')o.transport='standard';
   return original.call(this,bucket,path,file,o);
 }
 wrapped.__bingoTopicStandard=true;wrapped.__bingoOriginal=original;
 window.aaUploadStorageWithFeedback=wrapped;return true;
}


/* Live #28 transport authority: bypass the failing resumable host completely for Topic media.
   The topic row already exists before this function is called, so existing topic-media RLS remains authoritative. */
function installTopicUploader(){
 if(typeof window.aaUploadTopicMedia!=='function'||window.aaUploadTopicMedia.__bingoDirectStandard)return false;
 async function direct(files,userId,topicId,onProgress){
  var client=window.sb||window.supabase;
  if(!client)return {media:[],paths:[],error:new Error('No database connection. Bingo could not reach Supabase.')};
  if(!files||!files.length)return {media:[],paths:[],error:null};
  var media=[],paths=[];
  try{
   if(!userId)throw new Error('You must be logged in before uploading media.');
   if(!topicId)throw new Error('A topic ID is required before media can be stored.');
   for(var i=0;i<files.length;i++){
    var file=files[i],isVideo=/^video\//.test(String(file.type||''));
    if(typeof onProgress==='function')try{onProgress(i+1,files.length)}catch(_){}
    var safe=String(file.name||('topic-'+i)).replace(/[^a-zA-Z0-9._-]/g,'-');
    var path=userId+'/'+topicId+'/'+Date.now()+'-'+(i+1)+'-'+safe;
    var result=await client.storage.from('topic-media').upload(path,file,{upsert:false,contentType:file.type||(isVideo?'video/mp4':'image/jpeg'),cacheControl:'3600'});
    if(result&&result.error)throw result.error;
    paths.push(path);media.push({type:isVideo?'video':'image',path:path,name:file.name||safe});
   }
   return {media:media,paths:paths,error:null};
  }catch(error){
   if(paths.length)try{await client.storage.from('topic-media').remove(paths)}catch(_){}
   return {media:[],paths:[],error:new Error(String(error&&error.message||error||'Media upload failed.'))};
  }
 }
 direct.__bingoDirectStandard=true;
 window.aaUploadTopicMedia=direct;
 return true;
}

/* 129c39a/ad53a17: keep media natural, remove only genuine legacy Play overlays.
   Playback authority stays with the existing Home/Wall controllers. */
function cleanMedia(root){
 (root||document).querySelectorAll?.('#auto-arcade-widget video').forEach(function(v){
   v.playsInline=true;v.setAttribute('playsinline','');
 });
 (root||document).querySelectorAll?.('#auto-arcade-widget .aa-video-play-overlay').forEach(function(b){
   var card=b.closest('.aa360-item,.bingo-approved-topic');
   if(card)b.style.setProperty('display','none','important');
 });
}
/* Home/Wall: topic-media is PRIVATE and topic records store a path, not a URL.
   Repair only invalid public topic-media video URLs or explicit topic-media paths.
   Do not replace video elements, change layout, or touch Supabase records. */
function installPrivateTopicMediaResolver(){
 var pending=new WeakMap();
 async function repair(v){
  if(!v||!v.isConnected)return;
  var raw=v.currentSrc||v.getAttribute('src')||v.querySelector('source[src]')?.getAttribute('src')||v.dataset?.mediaPath||'';
  if(!raw||pending.get(v)===raw)return;
  var path='';
  /* Signed topic-media URLs are already playable; never re-sign or reload them. */
  if(/\/storage\/v1\/object\/sign\/topic-media\//.test(String(raw)) && /(?:[?&]token=)/.test(String(raw)))return;
  var match=String(raw).match(/\/storage\/v1\/object\/(?:public|authenticated)\/topic-media\/([^?#]+)/);
  if(match)path=decodeURIComponent(match[1]);
  else if(v.dataset?.mediaBucket==='topic-media'&&v.dataset?.mediaPath)path=v.dataset.mediaPath;
  if(!path)return;
  var client=window.sb||window.supabase;
  if(!client?.storage?.from)return;
  pending.set(v,raw);
  try{
   var signed=await client.storage.from('topic-media').createSignedUrl(path,3600);
   var url=signed?.data?.signedUrl;
   if(signed?.error||!url){pending.delete(v);return}
   if(!v.isConnected)return;
   var current=v.currentSrc||v.getAttribute('src')||v.querySelector('source[src]')?.getAttribute('src')||v.dataset?.mediaPath||'';
   if(current!==raw)return;
   var wasPaused=v.paused;
   var source=v.querySelector('source[src]');
   if(source)source.src=url;else v.src=url;
   v.load();
   if(!wasPaused&&v.isConnected)v.play().catch(function(){});
  }catch(_){pending.delete(v)}
 }
 function scan(root){
  if(root?.matches?.('video'))repair(root);
  root?.querySelectorAll?.('#auto-arcade-widget video').forEach(repair);
 }
 var queued=false;
 new MutationObserver(function(ms){
  if(queued)return;
  if(!ms.some(m=>m.type==='childList'||m.attributeName==='src'))return;
  queued=true;setTimeout(function(){queued=false;scan(document)},180);
 }).observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['src']});
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',function(){scan(document)},{once:true});
 else scan(document);
}
installPrivateTopicMediaResolver();

var tries=0,t=setInterval(function(){var a=installTopicTransport(),b=installTopicUploader();if((a&&b)||++tries>200)clearInterval(t)},50);
var q=0;new MutationObserver(function(ms){clearTimeout(q);q=setTimeout(function(){cleanMedia(document)},100)}).observe(document.documentElement,{childList:true,subtree:true});
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',function(){cleanMedia(document)},{once:true});else cleanMedia(document);
})();
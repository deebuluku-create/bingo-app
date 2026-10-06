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
var tries=0,t=setInterval(function(){if(installTopicTransport()||++tries>100)clearInterval(t)},50);
var q=0;new MutationObserver(function(ms){clearTimeout(q);q=setTimeout(function(){cleanMedia(document)},100)}).observe(document.documentElement,{childList:true,subtree:true});
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',function(){cleanMedia(document)},{once:true});else cleanMedia(document);
})();
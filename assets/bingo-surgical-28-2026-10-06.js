/* Bingo #28 surgical behavior patch — 2026-10-06. No data model changes. */
(function(){'use strict';if(window.__bingoSurgical281006)return;window.__bingoSurgical281006=1;
/* Profile grid: make video thumbnails decode a representative frame without starting feed playback. */
function primeGrid(root){
 (root||document).querySelectorAll?.('#auto-arcade-widget .bp-grid video').forEach(function(v){
  if(v.dataset.bingoGridReady)return;v.dataset.bingoGridReady='1';v.muted=true;v.playsInline=true;v.preload='metadata';
  function frame(){try{if(v.readyState>=1&&isFinite(v.duration)&&v.duration>0&&v.currentTime<.02)v.currentTime=Math.min(.15,Math.max(.02,v.duration*.01));v.pause()}catch(_){}}
  v.addEventListener('loadedmetadata',frame,{once:true});try{v.load()}catch(_){}
 });
}
/* Edit fallback: the master already owns aaOpenEditTopic; this only guarantees the menu click reaches it
   if another transient-panel listener consumes the click before the inline handler. */
document.addEventListener('pointerup',function(e){
 var b=e.target.closest?.('.bingo-topic-options button');if(!b)return;
 if(!/^\s*Edit post\s*$/i.test(b.textContent||''))return;
 var card=b.closest('.bingo-approved-topic');if(!card)return;
 var canon=card.getAttribute('data-canon')||'',id=canon.replace(/^topic:/,'');if(!id)return;
 setTimeout(function(){try{
  if(window.state&&String(state.topicEditId||'')===String(id))return;
  if(typeof window.aaOpenEditTopic==='function')window.aaOpenEditTopic(id);
 }catch(_){}},0);
},true);
var q=0;new MutationObserver(function(ms){clearTimeout(q);q=setTimeout(function(){primeGrid(document)},80)}).observe(document.documentElement,{childList:true,subtree:true});
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',function(){primeGrid(document)},{once:true});else primeGrid(document);
})();
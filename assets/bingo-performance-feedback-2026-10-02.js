/* Bingo global performance + bounded centered feedback. Presentation/runtime guard only. */
(function(){
 'use strict';
 var MAX_VISIBLE=60000, SUCCESS_VISIBLE=4500, ERROR_VISIBLE=9000, timer=0;
 function box(){
  var b=document.getElementById('bingoFastFeedback');
  if(!b){b=document.createElement('div');b.id='bingoFastFeedback';b.setAttribute('role','status');b.setAttribute('aria-live','polite');document.body.appendChild(b)}
  return b;
 }
 function show(msg,type,ms){
  if(!msg)return;
  var b=box(); clearTimeout(timer); b.textContent=String(msg); b.className='show '+(type||'ok');
  timer=setTimeout(function(){b.className='';},Math.min(Math.max(Number(ms)||SUCCESS_VISIBLE,1200),MAX_VISIBLE));
 }
 window.bingoFastFeedback=show;
 function successish(s){return /success|successful|uploaded|published|saved|created|signed up|welcome|complete|done/i.test(s||'')}
 function errorish(s){return /error|failed|unable|could not|try again/i.test(s||'')}
 /* Wrap existing toast without changing its behavior; mirror important results centrally and bound visibility. */
 function wrapToast(){
  if(typeof window.toast!=='function'||window.toast.__bingoFastWrapped)return;
  var old=window.toast;
  function wrapped(msg){
   var r=old.apply(this,arguments),s=String(msg||'');
   if(successish(s))show(s,'ok',SUCCESS_VISIBLE); else if(errorish(s))show(s,'err',ERROR_VISIBLE);
   return r;
  }
  wrapped.__bingoFastWrapped=true; window.toast=wrapped;
 }
 wrapToast();
 var wrapPoll=setInterval(wrapToast,500); setTimeout(function(){clearInterval(wrapPoll)},30000);
 /* Native lazy decoding for offscreen media; never lazy-load the logo or already-playing videos. */
 function tune(root){
  (root||document).querySelectorAll('img').forEach(function(el){
   if(!el.classList.contains('bingo-app-logo')&&!el.closest('.bingo-header-stack')){if(!el.loading)el.loading='lazy';el.decoding='async'}
  });
  (root||document).querySelectorAll('video').forEach(function(el){
   if(!el.autoplay&&!el.closest('.aa360-item'))el.preload='metadata';
  });
 }
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',function(){tune(document)},{once:true});else tune(document);
 var queued=false;
 new MutationObserver(function(){
  if(queued)return;queued=true;
  (window.requestIdleCallback||function(f){setTimeout(f,80)})(function(){queued=false;tune(document)});
 }).observe(document.documentElement,{childList:true,subtree:true});
 /* Safety: stale generic loading overlays cannot trap the UI for minutes.
    Only hide elements that explicitly identify themselves as loading/busy. */
 setInterval(function(){
  var now=Date.now();
  document.querySelectorAll('[aria-busy="true"],.loading-overlay,.upload-loading,.signup-loading').forEach(function(el){
   if(!el.dataset.bingoBusySince)el.dataset.bingoBusySince=String(now);
   if(now-Number(el.dataset.bingoBusySince)>MAX_VISIBLE){
    el.style.display='none';el.setAttribute('aria-busy','false');
    show('The operation is taking longer than expected. You can continue using Bingo and try again if needed.','err',ERROR_VISIBLE);
   }
  });
 },2000);
})();
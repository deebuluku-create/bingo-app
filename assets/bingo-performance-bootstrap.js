/* Bingo performance bootstrap — surgical runtime optimization, master HTML untouched */
(function(){
'use strict';
if(window.__bingoPerfBootstrap)return; window.__bingoPerfBootstrap=true;

/* Browser hints for off-screen media. Existing app behavior remains authoritative. */
function tuneMedia(root){
  const scope=root&&root.querySelectorAll?root:document;
  scope.querySelectorAll('img').forEach(function(img){
    if(!img.hasAttribute('decoding')) img.decoding='async';
    if(!img.hasAttribute('loading')) img.loading='lazy';
  });
  scope.querySelectorAll('video').forEach(function(v){
    if(!v.hasAttribute('preload')) v.preload='metadata';
    v.setAttribute('playsinline','');
  });
}

/* Home-feed video budget: keep visible/nearby posts warm, release distant videos.
   This reduces mobile bandwidth/decoder pressure while preserving tap/play controls. */
var io=null;
function installVideoBudget(){
  if(!('IntersectionObserver' in window))return;
  if(io)io.disconnect();
  io=new IntersectionObserver(function(entries){
    entries.forEach(function(e){
      var v=e.target;
      if(e.isIntersecting){
        if(v.preload==='none')v.preload='metadata';
      }else{
        try{ if(!v.paused)v.pause(); }catch(_){}
        if(Math.abs(e.boundingClientRect.top)>innerHeight*2.5) v.preload='none';
      }
    });
  },{rootMargin:'100% 0px 100% 0px',threshold:.01});
  document.querySelectorAll('video').forEach(function(v){io.observe(v)});
}

/* Batch DOM rescans instead of doing work for every mutation. */
var scheduled=false;
function schedule(){
  if(scheduled)return; scheduled=true;
  var run=function(){scheduled=false;tuneMedia(document);installVideoBudget()};
  if('requestIdleCallback' in window)requestIdleCallback(run,{timeout:800}); else setTimeout(run,80);
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',schedule,{once:true}); else schedule();
new MutationObserver(schedule).observe(document.documentElement,{childList:true,subtree:true});

/* Save-data/slow-network mode: avoid speculative video buffering. */
try{
  var c=navigator.connection||navigator.mozConnection||navigator.webkitConnection;
  if(c&&(c.saveData||/2g/.test(c.effectiveType||''))){
    document.addEventListener('DOMContentLoaded',function(){
      document.querySelectorAll('video').forEach(function(v){v.preload='none'});
    },{once:true});
  }
}catch(_){}
})();

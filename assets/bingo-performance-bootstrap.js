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
function installVideoBudget(root){
  if(!('IntersectionObserver' in window))return;
  if(!io)io=new IntersectionObserver(function(entries){
    entries.forEach(function(e){
      var v=e.target;
      /* Comments, keyboard and transient drawers must never pause/restart the active post.
         Only media that has actually left the extended feed viewport is released. */
      if(e.isIntersecting){
        if(v.preload==='none')v.preload='metadata';
      }else{
        var r=v.getBoundingClientRect(), far=r.bottom < -innerHeight || r.top > innerHeight*2;
        /* Never release media belonging to the currently painted Home slide merely because a
           transient overlay/render animation briefly changes its geometry. Only genuinely distant
           feed media is budgeted out. */
        var card=v.closest&&v.closest('.aa360-item');
        var activeHome=card&&window.state&&state.view==='home'&&
          (card.matches('.active,.is-active,[aria-current="true"]')||
           (r.top < innerHeight*.55 && r.bottom > innerHeight*.45));
        if(far&&!activeHome){
          try{if(!v.paused)v.pause()}catch(_){}
          v.preload='none';
        }
      }
    });
  },{rootMargin:'100% 0px 100% 0px',threshold:0});
  var scope=root&&root.querySelectorAll?root:document;
  if(scope.matches&&scope.matches('video')&&!scope.dataset.bingoBudget&&!scope.closest('.aa360-feed')&&!scope.classList.contains('bingo-wall-video')){scope.dataset.bingoBudget='1';io.observe(scope)}
  /* Home feed and Wall videos are budgeted by the master's own controllers (aaFeedVideoBudget,
     aaInitWallVideos); one authority per surface. */
  scope.querySelectorAll('video').forEach(function(v){if(v.dataset.bingoBudget||(v.closest&&v.closest('.aa360-feed'))||(v.classList&&v.classList.contains('bingo-wall-video')))return;v.dataset.bingoBudget='1';io.observe(v)});
}

/* Batch DOM rescans instead of doing work for every mutation. */
var scheduled=false,pendingRoots=new Set();
function schedule(records){
  if(records&&records.length)records.forEach(function(m){m.addedNodes.forEach(function(n){if(n.nodeType===1)pendingRoots.add(n)})});
  if(scheduled)return; scheduled=true;
  var run=function(){
    scheduled=false;
    var roots=pendingRoots.size?Array.from(pendingRoots):[document];pendingRoots.clear();
    roots.forEach(function(root){if(root===document||root.isConnected){tuneMedia(root);installVideoBudget(root)}});
  };
  if('requestIdleCallback' in window)requestIdleCallback(run,{timeout:800}); else setTimeout(run,80);
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',function(){schedule()},{once:true}); else schedule();
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

/* Splash watchdog — the logo may never trap the user.
   Normal app timing remains untouched; 60s is an absolute recovery ceiling. */
(function bingoSplashWatchdog(){
  var MAX_SPLASH_MS=60000, done=false;
  function visible(el){
    if(!el||!el.isConnected)return false;
    var s=getComputedStyle(el),r=el.getBoundingClientRect();
    return s.display!=='none'&&s.visibility!=='hidden'&&Number(s.opacity||1)>0&&r.width>0&&r.height>0;
  }
  function splashCandidates(){
    var app=document.getElementById('auto-arcade-widget');
    return Array.from(document.querySelectorAll('[id*="splash" i],[class*="splash" i],[id*="intro" i],[class*="intro" i]'))
      .filter(function(el){
        /* <body class="bingo-splash-done"> and the app itself (e.g. the logo's intro class) are never a
           splash: matching them kept this watchdog armed and at 60 s it hid <body> — a white screen. */
        if(el===document.documentElement||el===document.body)return false;
        if(app&&(el===app||el.contains(app)||app.contains(el)))return false;
        return visible(el);
      });
  }
  function release(){
    if(done)return; done=true;
    splashCandidates().forEach(function(el){
      el.style.setProperty('display','none','important');
      el.style.setProperty('pointer-events','none','important');
      el.setAttribute('aria-hidden','true');
    });
    document.documentElement.style.overflow='';
    document.body.style.overflow='';
    try{
      if(window.state) state.view='home';
      if(typeof window.goHome==='function') window.goHome();
      else if(typeof window.render==='function') window.render();
    }catch(_){}
  }
  /* If the app successfully leaves splash itself, cancel the forced recovery. */
  var watch=setInterval(function(){
    if(!splashCandidates().length){done=true;clearInterval(watch);clearTimeout(kill)}
  },500);
  var kill=setTimeout(function(){clearInterval(watch);release()},MAX_SPLASH_MS);
})();


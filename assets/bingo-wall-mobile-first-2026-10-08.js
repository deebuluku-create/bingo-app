/* Bingo Wall mobile-first behavior — 2026-10-08. Wall scope only. */
(function(){'use strict';if(window.__bingoWallMobileFirst20261008)return;window.__bingoWallMobileFirst20261008=true;
const ROOT='#auto-arcade-widget';
const ratios=new WeakMap();let io=null;
function page(){return document.querySelector(ROOT+' .bingo-topic-page')}
function wireVideo(v){
 if(v.dataset.bingoWallMobileFirst)return;v.dataset.bingoWallMobileFirst='1';
 v.autoplay=true;v.playsInline=true;v.setAttribute('playsinline','');v.controls=false;
 if(!v.preload||v.preload==='none')v.preload='metadata';
 v.addEventListener('click',function(e){e.stopPropagation();if(v.paused){const p=v.play();if(p&&p.catch)p.catch(()=>{})}else v.pause()},true);
 io.observe(v);
}
function install(){
 const p=page();if(!p)return;
 if(!io)io=new IntersectionObserver(entries=>{entries.forEach(e=>{ratios.set(e.target,e.intersectionRatio);if(e.intersectionRatio>=.55){p.querySelectorAll('video').forEach(o=>{if(o!==e.target&&!o.paused)try{o.pause()}catch(_){} });const q=e.target.play();if(q&&q.catch)q.catch(()=>{try{e.target.muted=true;const r=e.target.play();if(r&&r.catch)r.catch(()=>{})}catch(_){}})}else if(e.intersectionRatio<.2){try{e.target.pause()}catch(_){}}})},{threshold:[0,.2,.55,1]});
 p.querySelectorAll('video').forEach(wireVideo);
 p.querySelectorAll('.aa-video-play-overlay,.aa-wall-play,[class*="play-overlay"]').forEach(x=>x.style.display='none');
}
let queued=false;new MutationObserver(()=>{if(queued)return;queued=true;requestAnimationFrame(()=>{queued=false;install()})}).observe(document.documentElement,{childList:true,subtree:true});
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',install,{once:true});else install();
})();
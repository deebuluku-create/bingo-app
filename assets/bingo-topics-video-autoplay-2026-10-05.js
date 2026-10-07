/* Bingo Topics video autoplay — single-authority repair 2026-10-07.
   Scope ONLY: Bingo Topics video cards. No Home renderer, layout, posts, Supabase,
   profile/business data, orientation or navigation changes. */
(function(){
'use strict';
if(window.__bingoTopicsAutoplay20261007)return;window.__bingoTopicsAutoplay20261007=true;
const ROOT='#auto-arcade-widget', wired=new WeakSet(), ratios=new WeakMap();
let videos=[], scheduled=false;
const text=el=>(el&&el.textContent||'').replace(/\s+/g,' ').trim().toLowerCase();
function topicPage(){
 const r=document.querySelector(ROOT)||document;
 return [...r.querySelectorAll('h1,h2,h3,[role="heading"]')].some(x=>/bingo\s*topics?/i.test(x.textContent||''))||
   document.body.classList.contains('bingo-topic-page')||!!r.querySelector('.bingo-topic-page');
}
function topicCard(v){return v.closest('[data-topic-id],[data-bingo-topic],.bingo-topic-card,.topic-card,.bingo-approved-topic,.aa360-item,article,[data-post-id],.post,.feed-item')}
function hidePlay(card,v){
 if(!card)return;
 card.querySelectorAll('button,[role="button"],span,div').forEach(el=>{
  if(el===card||el.contains(v))return;
  const t=text(el),c=String(el.className||'').toLowerCase(),a=(el.getAttribute('aria-label')||'').toLowerCase();
  if((t==='▶'||t==='►'||t==='⏵'||t==='play'||a==='play'||/play[-_ ]?(overlay|button|icon)/.test(c))&&!el.querySelector('video')){
   el.style.setProperty('display','none','important');el.setAttribute('aria-hidden','true');
  }
 });
}
function apply(){
 scheduled=false;if(!topicPage())return;
 videos=videos.filter(v=>v.isConnected);
 let best=null,bestR=0;
 videos.forEach(v=>{const n=ratios.get(v)||0;if(n>bestR){best=v;bestR=n}});
 videos.forEach(v=>{
  if(v===best&&bestR>=.55){
   v.autoplay=true;v.playsInline=true;v.setAttribute('playsinline','');v.controls=false;
   if(v.paused){try{const p=v.play();if(p&&p.catch)p.catch(()=>{})}catch(_){}}
  }else if(v!==best&&!v.paused){try{v.pause()}catch(_){}}
 });
}
function schedule(){if(scheduled)return;scheduled=true;requestAnimationFrame(apply)}
const io=new IntersectionObserver(es=>{
 es.forEach(e=>ratios.set(e.target,e.intersectionRatio));
 schedule();
},{threshold:[0,.25,.55,.75,1]});
function wire(v){
 if(!topicPage()||wired.has(v))return;
 const card=topicCard(v);if(!card)return;
 wired.add(v);videos.push(v);v.autoplay=true;v.playsInline=true;v.setAttribute('playsinline','');v.controls=false;
 /* Never call load(), reset currentTime, replace src, or rewrite preload here. */
 io.observe(v);hidePlay(card,v);
}
function scan(root){
 if(!topicPage())return;
 if(root?.matches?.('video'))wire(root);
 root?.querySelectorAll?.('video').forEach(wire);
 videos.forEach(v=>hidePlay(topicCard(v),v));schedule();
}
let mt=0;
new MutationObserver(ms=>{
 clearTimeout(mt);mt=setTimeout(()=>{
  ms.forEach(m=>m.addedNodes.forEach(n=>{if(n.nodeType===1)scan(n)}));
 },120);
}).observe(document.documentElement,{childList:true,subtree:true});
document.addEventListener('visibilitychange',()=>{
 if(document.hidden)videos.forEach(v=>{try{v.pause()}catch(_){}});
 else schedule();
});
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>scan(document),{once:true});else scan(document);
})();
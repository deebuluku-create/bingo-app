/* Bingo Topics video autoplay — 2026-10-05. Surgical external patch only.
   Scope: Bingo Topics video cards. Does not alter layout, posting, comments, crowns,
   profiles, persistence, uploads, Home feed rendering, or unrelated navigation. */
(function(){
'use strict';
if(window.__bingoTopicsAutoplay20261005)return;window.__bingoTopicsAutoplay20261005=true;
const ROOT='#auto-arcade-widget';
const wired=new WeakSet(), ratios=new WeakMap();
let videos=[];
function text(el){return (el&&el.textContent||'').replace(/\s+/g,' ').trim().toLowerCase()}
function topicPage(){
 const r=document.querySelector(ROOT)||document;
 const h=[...r.querySelectorAll('h1,h2,h3,[role="heading"]')].some(x=>/bingo\s*topics?/i.test(x.textContent||''));
 return h||document.body.classList.contains('bingo-topic-page')||!!r.querySelector('.bingo-topic-page');
}
function topicCard(v){
 return v.closest('[data-topic-id],[data-bingo-topic],.bingo-topic-card,.topic-card,.bingo-approved-topic,.aa360-item,article,[data-post-id],.post,.feed-item');
}
function hidePlay(card,v){
 if(!card)return;
 card.querySelectorAll('button,[role="button"],span,div').forEach(el=>{
   if(el===card||el.contains(v))return;
   const t=text(el), c=String(el.className||'').toLowerCase(), a=(el.getAttribute('aria-label')||'').toLowerCase();
   if((t==='▶'||t==='►'||t==='⏵'||t==='play'||a==='play'||/play[-_ ]?(overlay|button|icon)/.test(c))&&!el.querySelector('video')){
     el.style.setProperty('display','none','important'); el.setAttribute('aria-hidden','true');
   }
 });
}
function ratio(v){
 const r=v.getBoundingClientRect(),vh=innerHeight||document.documentElement.clientHeight;
 return r.height?Math.max(0,Math.min(r.bottom,vh)-Math.max(r.top,0))/r.height:0;
}
function choose(){
 if(!topicPage())return;
 videos=videos.filter(v=>v.isConnected);
 let best=null,bestR=0;
 videos.forEach(v=>{const n=ratios.has(v)?ratios.get(v):ratio(v);if(n>bestR){best=v;bestR=n}});
 videos.forEach(v=>{
   if(v===best&&bestR>=.35){
     v.autoplay=true;v.playsInline=true;v.setAttribute('playsinline','');v.controls=false;
     let p;try{p=v.play()}catch(e){}
     if(p&&p.catch)p.catch(()=>{try{v.muted=true;const q=v.play();if(q&&q.catch)q.catch(()=>{})}catch(e){}});
   }else{try{v.pause()}catch(e){}}
 });
}
const io=new IntersectionObserver(es=>{es.forEach(e=>ratios.set(e.target,e.intersectionRatio));choose()},{threshold:[0,.35,.55,.75,1]});
function wire(v){
 if(!topicPage()||wired.has(v))return;
 const card=topicCard(v); if(!card)return;
 wired.add(v);videos.push(v);v.autoplay=true;v.playsInline=true;v.setAttribute('playsinline','');v.controls=false;io.observe(v);hidePlay(card,v);
 /* Do not consume video taps. The app's existing card/post click handler remains in control,
    so tapping the video opens the existing full Home-feed post with its comments/crowns. */
}
function scan(root){
 if(!topicPage())return;
 if(root&&root.matches&&root.matches('video'))wire(root);
 (root||document).querySelectorAll?.('video').forEach(wire);
 videos.forEach(v=>hidePlay(topicCard(v),v));choose();
}
let t=0;
new MutationObserver(ms=>{clearTimeout(t);t=setTimeout(()=>{ms.forEach(m=>m.addedNodes.forEach(n=>{if(n.nodeType===1)scan(n)}));scan(document)},90)}).observe(document.documentElement,{childList:true,subtree:true});
addEventListener('scroll',()=>{clearTimeout(t);t=setTimeout(choose,40)},{passive:true});
document.addEventListener('visibilitychange',()=>{if(document.hidden)videos.forEach(v=>{try{v.pause()}catch(e){}});else choose()});
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>scan(document),{once:true});else scan(document);
})();
/* Bingo video-feed viewport repair — 2026-10-05.
   Surgical runtime add-on only. No master rewrite, routing, persistence, upload,
   comments, crowns, shares, profiles or unrelated page structure is changed. */
(function(){
'use strict';
if(window.__bingoVideoFeedViewport)return;window.__bingoVideoFeedViewport=true;
const ROOT='#auto-arcade-widget';
const STYLE='bingoVideoFeedViewportCss';
const st=document.createElement('style');st.id=STYLE;st.textContent=`
/* Video is the dominant post surface. Preserve source aspect ratio; never stretch/crop it. */
${ROOT} .aa360-item video,
${ROOT} article video,
${ROOT} [data-post-id] video,
${ROOT} .post video,
${ROOT} .feed-item video,
${ROOT} [class*="wall"] video,
${ROOT} [class*="detail"] video{
 display:block!important;width:100%!important;height:auto!important;max-height:calc(100svh - 150px)!important;
 object-fit:contain!important;background:#000!important;border-radius:0!important
}
/* Native video chrome and legacy centre-play artwork are not the feed UI. Tap video = play/pause. */
${ROOT} video.bingo-viewport-video{cursor:pointer}
${ROOT} video.bingo-viewport-video::-webkit-media-controls{display:none!important}
${ROOT} .bingo-video-legacy-play{display:none!important}
/* Expanded Wall actions: keep existing click targets/wiring but remove bulky button boxes. */
html.bingo-video-wall ${ROOT} .bingo-video-word-action{
 background:transparent!important;border:0!important;box-shadow:none!important;border-radius:0!important;
 min-width:0!important;min-height:0!important;height:auto!important;padding:7px 9px!important;
 color:inherit!important;font-weight:800!important
}
html.bingo-video-wall ${ROOT} .bingo-video-word-action:hover,
html.bingo-video-wall ${ROOT} .bingo-video-word-action:focus-visible{text-decoration:underline!important;outline:none!important}
`;document.head.appendChild(st);

const vids=new Set();
const ratio=new WeakMap();
function visibleRatio(v){
 const r=v.getBoundingClientRect(), vh=innerHeight||document.documentElement.clientHeight;
 const shown=Math.max(0,Math.min(r.bottom,vh)-Math.max(r.top,0));
 return r.height?shown/r.height:0;
}
function pauseOthers(active){
 vids.forEach(v=>{if(v!==active&&!v.paused){try{v.pause()}catch(e){}}});
}
function playActive(){
 let best=null,bestR=0;
 vids.forEach(v=>{
   if(!v.isConnected){vids.delete(v);return}
   const n=ratio.has(v)?ratio.get(v):visibleRatio(v);
   if(n>bestR){bestR=n;best=v}
 });
 if(best&&bestR>=.55){
   pauseOthers(best);
   if(best.paused){
     const p=best.play();
     if(p&&typeof p.catch==='function')p.catch(function(){
       /* Browser autoplay policy may require muted first start. Never block the feed. */
       try{best.muted=true;const q=best.play();if(q&&q.catch)q.catch(()=>{});}catch(e){}
     });
   }
 }else pauseOthers(null);
}
const io=new IntersectionObserver(es=>{
 es.forEach(e=>ratio.set(e.target,e.intersectionRatio));
 playActive();
},{rootMargin:'0px',threshold:[0,.25,.55,.75,1]});

function wireVideo(v){
 if(!v||v.dataset.bingoViewportVideo)return;
 v.dataset.bingoViewportVideo='1';v.classList.add('bingo-viewport-video');
 v.autoplay=true;v.playsInline=true;v.setAttribute('playsinline','');v.preload='metadata';
 v.controls=false;vids.add(v);io.observe(v);
 v.addEventListener('loadedmetadata',playActive,{once:true});v.addEventListener('canplay',playActive,{once:true});
 v.addEventListener('click',function(e){
   e.stopPropagation();
   if(v.paused){pauseOthers(v);const p=v.play();if(p&&p.catch)p.catch(()=>{});}else v.pause();
 },true);
 /* Hide only a genuine overlay sitting in the same media host. */
 const host=v.parentElement;
 if(host){
   [...host.children].forEach(x=>{
     if(x===v||x.contains(v)||x.tagName==='SOURCE')return;
     const t=(x.textContent||'').replace(/\s+/g,'').trim().toLowerCase();
     const c=String(x.className||'').toLowerCase();
     if((t==='▶'||t==='play'||/play/.test(c))&&/^(BUTTON|DIV|SPAN)$/.test(x.tagName))x.classList.add('bingo-video-legacy-play');
   });
 }
}
function isWall(){
 const root=document.querySelector(ROOT);if(!root)return false;
 const labels=[...root.querySelectorAll('button,a,[role="button"]')].map(e=>(e.textContent||'').replace(/\s+/g,' ').trim().toLowerCase());
 return labels.includes('comment')&&labels.includes('share')&&labels.some(x=>x==='like'||x==='liked'||x==='crown'||x==='crowns');
}
function compactWall(){
 const wall=isWall();document.documentElement.classList.toggle('bingo-video-wall',wall);
 if(!wall)return;
 document.querySelectorAll(ROOT+' button,'+ROOT+' a[role="button"],'+ROOT+' [role="button"]').forEach(e=>{
   const t=(e.textContent||'').replace(/\s+/g,' ').trim().toLowerCase();
   if(['like','liked','comment','share','crown','crowns','save','saved'].includes(t))e.classList.add('bingo-video-word-action');
 });
}
function scan(root){
 if(root?.matches?.('video'))wireVideo(root);
 root?.querySelectorAll?.('video').forEach(wireVideo);
 compactWall();setTimeout(playActive,60);
}
let q=0;new MutationObserver(ms=>{
 clearTimeout(q);q=setTimeout(()=>{
   ms.forEach(m=>m.addedNodes.forEach(n=>{if(n.nodeType===1)scan(n)}));
   compactWall();playActive();
 },120);
}).observe(document.documentElement,{childList:true,subtree:true});
addEventListener('scroll',()=>{clearTimeout(q);q=setTimeout(playActive,90)},{passive:true});
addEventListener('resize',()=>{clearTimeout(q);q=setTimeout(playActive,90)},{passive:true});
document.addEventListener('visibilitychange',()=>{if(document.hidden)pauseOthers(null);else playActive()});
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>scan(document),{once:true});else scan(document);
})();
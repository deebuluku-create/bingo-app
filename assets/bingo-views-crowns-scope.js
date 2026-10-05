/* Bingo views/crowns scope guard — 2026-10-05.
   Surgical presentation scope only. Views/crown counters are visible only on Home,
   Bingo Wall/posts, or a surface that actually exposes a Crown action. No data/action wiring changed. */
(function(){'use strict';if(window.__bingoViewsCrownsScopeGuard)return;window.__bingoViewsCrownsScopeGuard=1;
const ROOT='#auto-arcade-widget',N=s=>(s||'').replace(/\s+/g,' ').trim();
const css=document.createElement('style');css.textContent='.bingo-vc-out-of-scope{display:none!important}';document.head.appendChild(css);
function view(){try{return String(window.state&&state.view||'').toLowerCase()}catch(_){return''}}
function allowedPage(){const v=view();return v==='home'||/topic|wall|post/.test(v)}
function crownActionNear(e){
 let n=e;for(let i=0;i<5&&n;i++,n=n.parentElement){
  if([...n.querySelectorAll('button,a,[role="button"]')].some(x=>/^crown(?:\s|$)/i.test(N(x.textContent))))return true;
 }return false;
}
function isCounter(e){const t=N(e.textContent);return /^\d+\s+views?\s*[·•]\s*(?:👑\s*)?\d+$/i.test(t)||/^\d+\s+views?\s*[·•]\s*\d+\s+watched$/i.test(t)}
function apply(){const r=document.querySelector(ROOT)||document.body;if(!r)return;
 [...r.querySelectorAll('*')].forEach(e=>{if(e.children.length>4||!isCounter(e))return;
   const ok=allowedPage()||crownActionNear(e);e.classList.toggle('bingo-vc-out-of-scope',!ok);e.setAttribute('aria-hidden',ok?'false':'true');
 });
}
let q=0;new MutationObserver(()=>{clearTimeout(q);q=setTimeout(apply,80)}).observe(document.documentElement,{childList:true,subtree:true,characterData:true});
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',apply,{once:true});else apply();
})();
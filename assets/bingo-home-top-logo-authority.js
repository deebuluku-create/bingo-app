/* Bingo Home top-logo authority — 2026-10-05.
   One surgical authority for the existing draggable Home logo.
   No post/video/crown/comment/share/sound wiring is changed. */
(function(){'use strict';if(window.__bingoHomeTopLogoAuthority)return;window.__bingoHomeTopLogoAuthority=1;
const ROOT='#auto-arcade-widget',N=s=>(s||'').replace(/\s+/g,' ').trim();
const css=document.createElement('style');css.textContent=`
html.bingo-home-top-logo .bingo-home-top-logo-box{position:fixed!important;left:18px!important;top:4px!important;right:auto!important;bottom:auto!important;transform:none!important;margin:0!important;z-index:2147481200!important}\nhtml.bingo-home-top-logo .bingo-home-top-stats{position:fixed!important;left:18px!important;top:92px!important;right:auto!important;bottom:auto!important;transform:none!important;margin:0!important;z-index:2147481199!important}
`;document.head.appendChild(css);
function home(){try{return !!(window.state&&state.view==='home')}catch(_){return false}}
function logo(){
 const r=document.querySelector(ROOT)||document;
 return [...r.querySelectorAll('img')].find(i=>(i.currentSrc||i.src||'').toLowerCase().includes('bingo-original-logo.png'))||null;
}
function box(img){if(!img)return null;let n=img;for(let i=0;i<4&&n;i++,n=n.parentElement){
 const z=n.getBoundingClientRect();if(z.width>=80&&z.width<=300&&z.height>=45&&z.height<=190&&[...n.querySelectorAll('button,[role="button"]')].some(b=>/^[×x✕]$/i.test(N(b.textContent))))return n}return img.parentElement}
function apply(){
 if(!home()){document.documentElement.classList.remove('bingo-home-top-logo');return}
 const b=box(logo());if(!b)return;
 document.documentElement.classList.add('bingo-home-top-logo');b.classList.remove('bingo-home-logo-audio-item');b.classList.add('bingo-home-top-logo-box');
 /* Inline reset is deliberate: retires the obsolete audio-row/static placement only on this existing logo. */
 b.style.setProperty('position','fixed','important');b.style.setProperty('left','18px','important');b.style.setProperty('top','4px','important');
 b.style.setProperty('right','auto','important');b.style.setProperty('bottom','auto','important');b.style.setProperty('transform','none','important');\n const r=document.querySelector(ROOT)||document;[...r.querySelectorAll('*')].forEach(e=>{if(e.children.length>3)return;const t=N(e.textContent);if(/^\\d+\\s+views?\\s*[·•]\\s*(?:👑\\s*)?\\d+$/i.test(t)){e.classList.add('bingo-home-top-stats')}});
}
let q=0;new MutationObserver(()=>{if(!home())return;clearTimeout(q);q=setTimeout(apply,100)}).observe(document.documentElement,{childList:true,subtree:true});
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',apply,{once:true});else apply();
})();
/* Bingo Duty 1 correction — logo isolation + circular Home feed, 2026-10-06.
   Surgical: Home only. No data/render/layout ownership changes. */
(function(){
'use strict';
if(window.__bingoDuty1LoopFix)return; window.__bingoDuty1LoopFix=true;

function home(){try{return !!(window.state&&state.view==='home')}catch(e){return false}}
function feed(){return document.querySelector('#auto-arcade-widget .aa360-feed')}
function items(f){return f?[...f.querySelectorAll('.aa360-item')]:[]}
function go(i){
 const f=feed(),a=items(f); if(!f||a.length<2)return;
 i=(i+a.length)%a.length;
 window.__bingoFeedTarget={index:i,at:Date.now()};
 if(typeof window.aaFeedGoTo==='function'){window.aaFeedGoTo(i,'auto');return}
 const h=f.clientHeight||a[0].clientHeight||1;
 f.scrollTop=i*h;
 window.__bingoFeedSettled=i;
 setTimeout(()=>{try{if(typeof window.aaInit360Feed==='function')window.aaInit360Feed()}catch(e){}},0);
}
function index(f,a){const h=f.clientHeight||a[0]?.clientHeight||1;return Math.max(0,Math.min(a.length-1,Math.round(f.scrollTop/h)))}

/* Circular navigation is only used at a real end. Native snap scrolling owns every middle swipe. */
document.addEventListener('wheel',function(e){
 if(!home()||Math.abs(e.deltaY)<8)return;
 const f=feed(),a=items(f);if(!f||a.length<2||!f.contains(e.target))return;
 const i=index(f,a);
 if(e.deltaY>0&&i===a.length-1){e.preventDefault();go(0)}
 else if(e.deltaY<0&&i===0){e.preventDefault();go(a.length-1)}
},{passive:false,capture:true});
let sy=null;
document.addEventListener('touchstart',e=>{if(home()&&feed()?.contains(e.target)&&e.touches.length===1)sy=e.touches[0].clientY;else sy=null},{passive:true,capture:true});
document.addEventListener('touchend',e=>{
 if(sy==null||!home())return;const y=e.changedTouches?.[0]?.clientY,dy=y==null?0:y-sy;sy=null;if(Math.abs(dy)<38)return;
 const f=feed(),a=items(f);if(!f||a.length<2)return;const i=index(f,a);
 if(dy<0&&i===a.length-1)go(0);else if(dy>0&&i===0)go(a.length-1);
},{passive:true,capture:true});

/* Once the original logo reaches its intended Home corner after splash, keep that same floating
   wrapper out of feed layout/re-render ownership. Dragging remains possible because only automatic
   corner-to-corner style churn is rejected; pointer activity temporarily releases the lock. */
let locked=null,drag=false;
function logoWrap(){
 const img=[...document.images].find(x=>(x.getAttribute('src')||'').includes('/assets/bingo-original-logo.png'));
 if(!img)return null;
 let n=img;for(let k=0;k<5&&n.parentElement;k++,n=n.parentElement){
   const s=getComputedStyle(n);if(s.position==='fixed'||s.position==='absolute')return n;
 }
 return img.parentElement;
}
function readyToLock(w){
 if(!home()||!document.body.classList.contains('bingo-splash-done'))return false;
 const r=w.getBoundingClientRect();return r.left<Math.max(40,innerWidth*.08)&&r.top<Math.max(70,innerHeight*.12);
}
function lock(w){
 const r=w.getBoundingClientRect();
 locked={w,left:r.left,top:r.top};
 w.style.position='fixed';w.style.left=r.left+'px';w.style.top=r.top+'px';w.style.margin='0';
 w.style.transform='none';w.style.zIndex=Math.max(1000,Number(getComputedStyle(w).zIndex)||0);
 w.style.contain='layout style';
 w.addEventListener('pointerdown',()=>{drag=true},{passive:true});
 addEventListener('pointerup',()=>{if(!drag)return;drag=false;requestAnimationFrame(()=>{const q=w.getBoundingClientRect();locked.left=q.left;locked.top=q.top})},{passive:true});
}
let tries=0;
const watch=setInterval(()=>{
 const w=logoWrap();if(!locked&&w&&readyToLock(w))lock(w);
 if(locked&&locked.w.isConnected&&!drag&&home()){
   const r=locked.w.getBoundingClientRect();
   if(Math.abs(r.left-locked.left)>2||Math.abs(r.top-locked.top)>2){
     locked.w.style.left=locked.left+'px';locked.w.style.top=locked.top+'px';locked.w.style.transform='none';
   }
 }
 if(++tries>120&&!locked)clearInterval(watch);
},250);
})();
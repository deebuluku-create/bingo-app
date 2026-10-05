/* Bingo mobile stability + transient-panel UX — surgical addon 2026-10-05 (revised 2026-10-05 b).
   1. Comment drafts survive a reload/white screen: saved per comment box, cleared once sent.
   2. Media lifecycle stays with bingo-performance-bootstrap.js (no second observer here).
   3. Tapping outside an open Comments style popover, the Create Post ⋮ menu, the 50-font Text
      Style panel, a profile ⋮ menu or a live-comment ••• menu closes it, and that same tap is
      swallowed so the control underneath does not fire. */
(function(){'use strict';
if(window.__bingoMobileStability20261005)return;window.__bingoMobileStability20261005=1;

/* ---------- 1. comment drafts ---------- */
const DRAFT='bingo_comment_draft_v2:';
const isCommentBox=el=>!!(el&&el.id&&/^topicComment_/.test(el.id));
const store={get(k){try{return sessionStorage.getItem(DRAFT+k)||''}catch(e){return ''}},set(k,v){try{if(v)sessionStorage.setItem(DRAFT+k,v);else sessionStorage.removeItem(DRAFT+k)}catch(e){}}};
document.addEventListener('input',e=>{if(isCommentBox(e.target))store.set(e.target.id,e.target.value||'')},true);
function clearFor(id){if(id)store.set(id,'')}
document.addEventListener('click',e=>{const send=e.target.closest?.('.bingo-topic-send');if(!send)return;const box=send.closest('.bingo-topic-composer')?.querySelector('input[id^="topicComment_"]');clearFor(box?.id)},true);
document.addEventListener('keydown',e=>{if(e.key==='Enter'&&!e.shiftKey&&isCommentBox(e.target))clearFor(e.target.id)},true);
function restoreDrafts(root){(root.querySelectorAll?root.querySelectorAll('input[id^="topicComment_"]'):[]).forEach(el=>{if(el.value)return;const v=store.get(el.id);if(!v)return;el.value=v;el.dispatchEvent(new Event('input',{bubbles:true}))})}

/* ---------- 2. media ----------
   Media lifecycle is owned exclusively by bingo-performance-bootstrap.js: no second video observer
   here (comments/keyboard change the viewport and must never pause the active post). */
let pending=0;
new MutationObserver(()=>{if(pending)return;pending=setTimeout(()=>{pending=0;restoreDrafts(document)},150)}).observe(document.documentElement,{childList:true,subtree:true});
window.addEventListener('pagehide',()=>document.querySelectorAll('video').forEach(v=>{try{v.pause()}catch(e){}}));

/* ---------- 3. outside-tap closes the open surface without firing what is underneath ---------- */
const shown=el=>!!el&&el.isConnected&&!el.hidden&&el.getClientRects().length>0;
const SURFACES=[
 {find:()=>document.querySelector('#bingo50-panel.open'),trigger:'.aa-composer-more,.bingo50-trigger,[data-bingo50-open]',close:p=>p.classList.remove('open')},
 {find:()=>document.querySelector('#auto-arcade-widget .aa-composer-menu'),trigger:'.aa-composer-more',close:()=>{if(typeof aaComposerToggleMenu==='function')aaComposerToggleMenu(false)}},
 {find:()=>document.querySelector('.bingo-cfmt-popover'),trigger:'[aria-label="Text style and display name"]',close:()=>{if(window.state){state.commentFmtPopoverFor=null;if(typeof render==='function')render()}}},
 {find:()=>window.state&&state.bpDotsOpen?document.querySelector('#auto-arcade-widget .bp-dots-pop,#auto-arcade-widget [role="menu"].bp-dots-menu'):null,trigger:'.bp-dots-btn',close:()=>{if(typeof aaBpToggleDots==='function')aaBpToggleDots(false)}},
 {find:()=>document.querySelector('.live-item-popover:not([hidden])'),trigger:'.live-item-dots',close:()=>{if(typeof aaLiveCloseOpenMenu==='function')aaLiveCloseOpenMenu()}}
];
let swallowUntil=0;
document.addEventListener('pointerdown',e=>{
 swallowUntil=0; /* each new tap starts fresh: only the tap that closed a surface is swallowed */
 for(const s of SURFACES){
  let p=null;try{p=s.find()}catch(x){}
  if(!shown(p))continue;
  if(p.contains(e.target))return;
  if(e.target.closest?.(s.trigger))return;
  try{s.close(p)}catch(x){}
  swallowUntil=Date.now()+700;
  return;
 }
},true);
const swallow=e=>{if(Date.now()<swallowUntil){e.preventDefault();e.stopImmediatePropagation();if(e.type==='click')swallowUntil=0}};
window.addEventListener('click',swallow,true);
window.addEventListener('mouseup',swallow,true);

restoreDrafts(document);
})();

/* Profile grid preview repair: videos need a representative frame even when feed playback
   is aggressively budgeted. Scope is the visible Profile Posts/Reels/Saved surface only. */
(function(){'use strict';if(window.__bingoProfileGridPreview)return;window.__bingoProfileGridPreview=1;
function page(){var t=document.body?.innerText||'';return /\bPosts\b/.test(t)&&/\bReels\b/.test(t)&&/\bSaved\b/.test(t)&&/\bProfile\b/.test(t)}
function fix(v){if(!page()||v.dataset.bingoGridPreview)return;var r=v.getBoundingClientRect();if(r.width<60||r.height<60)return;
 v.dataset.bingoGridPreview='1';v.muted=true;v.setAttribute('playsinline','');v.preload='metadata';
 var show=function(){try{v.pause();if(v.readyState>=1&&isFinite(v.duration)&&v.duration>0&&v.currentTime===0)v.currentTime=Math.min(.12,Math.max(.01,v.duration*.01))}catch(_){}};
 v.addEventListener('loadedmetadata',show,{once:true});try{v.load()}catch(_){}}
function scan(){if(page())document.querySelectorAll('video').forEach(fix)}
let q=0;new MutationObserver(()=>{clearTimeout(q);q=setTimeout(scan,180)}).observe(document.documentElement,{childList:true,subtree:true});
document.addEventListener('click',()=>setTimeout(scan,150),true);if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',scan,{once:true});else scan();
})();
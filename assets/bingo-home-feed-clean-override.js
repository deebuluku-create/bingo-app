/* Bingo Home Feed surgical UI override — external, master HTML untouched */
(function(){
'use strict';
const S='bingo-feed-surgical-v1';
if(document.getElementById(S)) return;
const st=document.createElement('style'); st.id=S; st.textContent=`
/* Keep video/media dominant; remove legacy chrome injected around Home feed */
.bingo-feed-clean-avatar{position:absolute;right:18px;bottom:132px;width:52px;height:52px;border-radius:50%;object-fit:cover;border:2px solid #ffc928;z-index:30;box-shadow:0 0 12px rgba(255,201,40,.55);cursor:pointer}
.bingo-feed-clean-avatar-wrap{position:absolute;inset:0;pointer-events:none;z-index:29}
.bingo-feed-clean-avatar-wrap .bingo-feed-clean-avatar{pointer-events:auto}
.bingo-comments-sheet{position:fixed;left:0;right:0;bottom:0;height:min(72vh,720px);background:#fff;color:#111;border-radius:22px 22px 0 0;z-index:2147483000;display:flex;flex-direction:column;box-shadow:0 -10px 40px #0007}
.bingo-comments-sheet[hidden]{display:none}
.bingo-comments-head{height:58px;display:flex;align-items:center;justify-content:center;font-weight:900;font-size:18px;border-bottom:1px solid #eee;position:relative}
.bingo-comments-close{position:absolute;right:18px;border:0;background:transparent;font-size:30px;cursor:pointer;color:#555}
.bingo-comments-body{flex:1;overflow:auto;padding:8px 16px 84px}
.bingo-comments-compose{position:absolute;left:0;right:0;bottom:0;min-height:68px;background:#fff;border-top:1px solid #eee;display:flex;align-items:center;gap:10px;padding:9px 14px}
.bingo-comments-compose input{flex:1;border:0;background:#f2f2f2;border-radius:24px;padding:13px 16px;font-size:16px}
#bingoHomeFeedWaiting{min-height:70vh;display:flex;align-items:center;justify-content:center}
.bingo-home-loading{display:flex;flex-direction:column;align-items:center;gap:12px;color:#9caecc;font-size:13px;font-weight:600}
.bingo-home-spinner{width:30px;height:30px;border-radius:50%;border:3px solid rgba(245,185,30,.25);border-top-color:#f5b91e;animation:bingoHomeSpin .8s linear infinite}
@keyframes bingoHomeSpin{to{transform:rotate(360deg)}}
`; document.head.appendChild(st);

const norm=s=>(s||'').replace(/\s+/g,' ').trim().toLowerCase();
function textEls(label){return [...document.querySelectorAll('button,a,span,div')].filter(e=>norm(e.textContent)===norm(label));}
function hideLegacy(){
  ['All Kenya','Following','Videos','Photos'].forEach(t=>textEls(t).forEach(e=>{const b=e.closest('button,a')||e;e.style.display='none'}));
  textEls('POST').forEach(e=>{const b=e.closest('button,a')||e;b.style.display='none'});
  [...document.querySelectorAll('button')].forEach(b=>{if(norm(b.textContent)==='▶'||norm(b.textContent)==='play') b.style.display='none'});
  [...document.querySelectorAll('a,button')].filter(e=>norm(e.textContent).includes('view profile')).forEach(link=>{
    const card=link.parentElement;
    if(!card||card.dataset.bingoCleaned) return;
    card.dataset.bingoCleaned='1';
    const img=card.querySelector('img');
    const href=link.getAttribute('href');
    const onclick=link.getAttribute('onclick');
    if(img){
      const clone=img.cloneNode(true); clone.className='bingo-feed-clean-avatar';
      clone.alt='Open profile'; clone.title='Open profile';
      if(href) clone.onclick=()=>location.href=href;
      else if(onclick) clone.setAttribute('onclick',onclick);
      else clone.onclick=()=>link.click();
      const host=card.closest('article,[data-post-id],.post,.feed-item,.aa-feed-card')||card.parentElement;
      if(host){ if(getComputedStyle(host).position==='static') host.style.position='relative'; host.appendChild(clone); }
    }
    card.style.display='none';
  });
}
function ensureSheet(){
 if(document.getElementById('bingoCommentsSheet')) return;
 const sh=document.createElement('section'); sh.id='bingoCommentsSheet'; sh.className='bingo-comments-sheet'; sh.hidden=true;
 sh.innerHTML='<div class="bingo-comments-head"><span id="bingoCommentsTitle">Comments</span><button class="bingo-comments-close" aria-label="Close comments">×</button></div><div class="bingo-comments-body" id="bingoCommentsBody"></div><div class="bingo-comments-compose"><input id="bingoCommentInput" placeholder="Add comment…" aria-label="Add comment"><span>▧</span><span>☺</span><span>@</span></div>';
 document.body.appendChild(sh);
 sh.querySelector('.bingo-comments-close').onclick=()=>sh.hidden=true;
}
function wireComments(){
 ensureSheet();
 [...document.querySelectorAll('button,a')].forEach(el=>{
   const t=norm(el.textContent);
   if((t.includes('comment')||t.includes('view post & comments'))&&!el.dataset.bingoCommentWire){
     el.dataset.bingoCommentWire='1';
     el.addEventListener('click',()=>{setTimeout(()=>{const sh=document.getElementById('bingoCommentsSheet'); if(sh) sh.hidden=false},0)},true);
   }
 });
}
function run(){hideLegacy();wireComments();}
/* Debounced for the same reason as bingoBrokenAgentModalGuard below: this
   scans the whole document (button,a,span,div - a huge match set on this
   app) on every single DOM mutation, with no coalescing. That is fine
   under light/idle activity but compounds into a creeping freeze under
   heavy render activity (confirmed: a rapid sequence of real UI clicks,
   each triggering a full render(), progressively lost responsiveness and
   the page eventually had to be force-closed). Coalescing into at most
   one scan per 300ms window keeps the exact same behavior, bounded. */
let runPending=false;
function scheduleRun(){
 if(runPending)return; runPending=true;
 setTimeout(()=>{runPending=false;run()},300);
}
new MutationObserver(scheduleRun).observe(document.documentElement,{childList:true,subtree:true});
run();
})();

/* Canonical Home guard: never show the retired 360View empty landing.
   Home remains the swipe feed surface and re-renders when async post data arrives.

   FIXED (same investigation as the MutationObserver freeze above): the
   placeholder below used to render as a literally empty div on the app's
   own near-black background (#030713) with NO loading indicator, and the
   poll that watches for real feed data gave up permanently after exactly
   10 seconds (40 x 250ms) with no fallback of any kind. On a real network
   - slower Supabase round-trips, cold starts, auth timing - 10 seconds is
   not a safe upper bound. Once it expired, a visitor was left staring at
   a visually indistinguishable-from-black screen forever, which is what
   "logo disappears, screen stays black" actually was: not a second freeze,
   a silent give-up with nothing shown in its place. Confirmed by a local
   Playwright run through the real index.php entrypoint that measured the
   screenshot's own pixel data (not just DOM state) after a fresh, 20-second
   wait: 98.6% of sampled pixels were black.
   Fixed two ways, both additive, neither changes the Home Feed's actual
   design once content loads:
   1. A small, dark-theme spinner + "Loading your feed..." label now
      renders inside the placeholder immediately, so the screen is never
      visually blank even during a legitimate brief load.
   2. The poll no longer gives up after 10 seconds. It keeps checking
      every 250ms up to a 5-minute safety ceiling (1200 tries) instead of
      a 10-second one - real data arriving at any point up to that ceiling
      still replaces the placeholder immediately. */
(function installBingoHomeFeedGuard(){
 function install(){
   if(typeof window.homeHTML!=='function'||window.__bingoHomeFeedGuard)return false;
   window.__bingoHomeFeedGuard=true;
   const original=window.homeHTML;
   window.homeHTML=function(boosted,rows,all,pages){
     let items=[]; try{items=typeof window.aaMixedFeedItems==='function'?window.aaMixedFeedItems():[]}catch(e){}
     if(items&&items.length) return original.apply(this,arguments);
     return '<section class="aa360-shell"><div class="aa360-feed" id="bingoHomeFeedWaiting" aria-live="polite">'
       + '<div class="bingo-home-loading"><span class="bingo-home-spinner"></span><span>Loading your feed&hellip;</span></div>'
       + '</div></section>';
   };
   let tries=0;
   const timer=setInterval(function(){
     tries++;
     try{
       if(window.state&&state.view==='home'&&typeof window.aaMixedFeedItems==='function'&&aaMixedFeedItems().length){
         clearInterval(timer); if(typeof window.render==='function')render();
       } else if(tries>=1200) clearInterval(timer);
     }catch(e){if(tries>=1200)clearInterval(timer)}
   },250);
   return true;
 }
 if(!install()){
   let n=0,t=setInterval(()=>{if(install()||++n>40)clearInterval(t)},100);
 }
})();

/* Emergency stale/broken modal guard: remove raw-template Agent invitation overlay
   if it ever leaks into the public landing route; return Home to feed. */
(function bingoBrokenAgentModalGuard(){
 const bad='invite a bingo agent';
 function clean(){
   /* Narrowed from a whole-document div/section/aside/dialog scan (tens
      of thousands of matches on this app, each requiring a full-subtree
      textContent concatenation, re-run on every single DOM mutation
      anywhere on the page) down to only the handful of actual modal/
      overlay containers the leaked template could ever render inside.
      The former created a self-sustaining MutationObserver storm: this
      app's own normal operation (ticker/animation/render churn) keeps
      mutating the DOM, each mutation re-triggered the full scan, and the
      resulting CPU saturation never let go - confirmed by isolating this
      exact IIFE alone against the mother HTML: the page never recovered
      within 15+ seconds of wall time, which is what presented as "Home
      Feed never appears after the opening montage." */
   const candidates=[...document.querySelectorAll('[role="dialog"],dialog,.modal,.overlay,.sheet')];
   for(const modal of candidates){
     const txt=(modal.textContent||'').toLowerCase();
     if(txt.includes(bad) && (txt.includes('${') || txt.includes('foundagent') || txt.includes('perms.map'))){
       modal.remove();
       document.body.style.overflow='';
       document.documentElement.style.overflow='';
       try{
         if(window.state) state.view='home';
         if(typeof window.goHome==='function') window.goHome();
         else if(typeof window.render==='function') window.render();
       }catch(e){}
       break;
     }
   }
 }
 /* Debounced: a burst of mutations elsewhere in the app now triggers at
    most one check per 300ms window instead of one full scan per
    individual mutation record - same detection, bounded cost. */
 let pending=false;
 function schedule(){
   if(pending)return; pending=true;
   setTimeout(()=>{pending=false;clean()},300);
 }
 new MutationObserver(schedule).observe(document.documentElement,{childList:true,subtree:true});
 if(document.readyState==='loading') document.addEventListener('DOMContentLoaded',clean,{once:true}); else clean();
})();

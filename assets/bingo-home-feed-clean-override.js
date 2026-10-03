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


/* Startup media priority: once the canonical Home feed exists, give only the
   first visible video eager buffering and immediately hand playback to the
   app's existing aaInit360Feed controller. Off-screen 4K videos remain
   metadata/lazy so they do not compete with the first frame for bandwidth. */
(function installBingoFirstVideoPriority(){
 let pending=false;
 function prioritize(){
  pending=false;
  try{
   if(String(window.state?.view||'home')!=='home')return;
   const videos=[...document.querySelectorAll('#auto-arcade-widget .aa360-feed video.aa360-video')];
   if(!videos.length)return;
   const first=videos[0];
   /* Never allow more than the active/next media to compete for mobile bandwidth. */
   videos.slice(2).forEach(v=>{try{if(!v.paused)v.pause()}catch(e){};v.preload='metadata';});
   videos.forEach((v,i)=>{v.preload=i<2?'auto':'metadata';v.playsInline=true;v.setAttribute('playsinline','');});
   if(first.dataset.bingoStartupPriority==='1')return;
   first.dataset.bingoStartupPriority='1';
   if(first.readyState<2){try{first.load()}catch(e){}}
   /* Warm the next post without decoding every heavy video. */
   if(videos[1]&&videos[1].readyState===0){try{videos[1].load()}catch(e){}}
   requestAnimationFrame(()=>{try{if(typeof window.aaInit360Feed==='function')window.aaInit360Feed()}catch(e){}});
  }catch(e){}
 }
 function schedule(){
  if(pending)return;pending=true;
  setTimeout(prioritize,80);
 }
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',schedule,{once:true});else schedule();
 new MutationObserver(schedule).observe(document.documentElement,{childList:true,subtree:true});
 window.addEventListener('pageshow',schedule);
})();


/* Bingo approved mobile Home surface — 2026-10-03 */
(function installApprovedBingoMobileHome(){
'use strict';
if(window.__bingoApprovedMobileHome)return; window.__bingoApprovedMobileHome=true;
const ICON={
 speakerOn:'<svg viewBox="0 0 32 32" aria-hidden="true"><path fill="white" d="M4 12v8h6l7 6V6l-7 6H4z"/><path d="M21 11c2.5 2.5 2.5 7.5 0 10M24 8c4.5 4.5 4.5 11.5 0 16" fill="none" stroke="#35b8ff" stroke-width="2.8" stroke-linecap="round"/></svg>',
 speakerOff:'<svg viewBox="0 0 32 32" aria-hidden="true"><path fill="white" d="M4 12v8h6l7 6V6l-7 6H4z"/><path d="M20 9l9 14" stroke="#ff4b55" stroke-width="3.2" stroke-linecap="round"/></svg>',
 crown:'<svg viewBox="0 0 32 32"><path fill="#ffc928" d="M4 10l6 5 6-10 6 10 6-5-3 15H7z"/><path fill="none" stroke="#ffe47a" stroke-width="1.4" d="M7 25h18"/></svg>',
 comment:'<svg viewBox="0 0 32 32"><path d="M5 6h22v16H14l-7 5v-5H5z" fill="none" stroke="white" stroke-width="2.4" stroke-linejoin="round"/><circle cx="11" cy="14" r="1.3" fill="white"/><circle cx="16" cy="14" r="1.3" fill="white"/><circle cx="21" cy="14" r="1.3" fill="white"/></svg>',
 share:'<svg viewBox="0 0 32 32"><path d="M5 25c4-9 10-11 17-11V8l6 7-6 7v-5c-7 0-12 2-17 8z" fill="none" stroke="white" stroke-width="2.4" stroke-linejoin="round"/></svg>',
 home:'<svg viewBox="0 0 32 32"><path d="M4 15L16 5l12 10v13h-9v-8h-6v8H4z" fill="currentColor"/></svg>',
 live:'<svg viewBox="0 0 32 32"><rect x="5" y="8" width="17" height="16" rx="1" fill="none" stroke="currentColor" stroke-width="2.3"/><path d="M22 13l6-4v14l-6-4z" fill="currentColor"/></svg>',
 market:'<svg viewBox="0 0 32 32"><path d="M5 12h22l-2-6H7zM7 14v13h18V14M12 27v-8h8v8" fill="none" stroke="currentColor" stroke-width="2.2"/></svg>',
 messages:'<svg viewBox="0 0 32 32"><path d="M5 6h22v17H14l-7 5v-5H5z" fill="none" stroke="currentColor" stroke-width="2.2"/><circle cx="11" cy="14" r="1.2" fill="currentColor"/><circle cx="16" cy="14" r="1.2" fill="currentColor"/><circle cx="21" cy="14" r="1.2" fill="currentColor"/></svg>'
};
const css=document.createElement('style');css.id='bingo-approved-mobile-home-css';css.textContent=`
@media(max-width:820px){
 html,body{width:100%;max-width:100%;overflow-x:hidden}
 body.bingo-approved-home{background:#030713!important}
 body.bingo-approved-home #auto-arcade-widget{width:100%!important;max-width:none!important;margin:0!important}
 body.bingo-approved-home .aa360-shell,body.bingo-approved-home .aa360-feed{width:100%!important;max-width:none!important;margin:0!important}
 body.bingo-approved-home .aa360-feed{height:100dvh!important;scroll-snap-type:y mandatory!important;overflow-y:auto!important}
 body.bingo-approved-home .aa360-feed>article,body.bingo-approved-home .aa360-feed>[data-post-id],body.bingo-approved-home .aa360-feed>.aa360-item{min-height:100dvh!important;height:100dvh!important;scroll-snap-align:start!important;position:relative!important;background:#030713!important}
 body.bingo-approved-home video.aa360-video{width:100%!important;height:100%!important;object-fit:cover!important;display:block!important}
 .bingo-approved-top{position:fixed;z-index:2147482000;top:max(12px,env(safe-area-inset-top));left:14px;right:14px;height:48px;display:flex;align-items:center;pointer-events:none}
 .bingo-approved-logo{font:900 28px/1 Arial,sans-serif;color:#ffc928;text-shadow:0 0 10px #f0a900;pointer-events:auto}
 .bingo-approved-filters{position:absolute;left:50%;transform:translateX(-50%);display:flex;gap:7px;pointer-events:auto}
 .bingo-approved-filter{border:1px solid #48505e;background:#111722;color:#fff;border-radius:18px;padding:8px 13px;font:700 12px Arial}
 .bingo-approved-filter.active{border-color:#ffc928;box-shadow:0 0 12px #ffc928;color:#fff}
 .bingo-approved-speaker{position:absolute;right:0;border:0;background:transparent!important;padding:0;width:36px;height:36px;pointer-events:auto}
 .bingo-approved-speaker svg{width:36px;height:36px;display:block}
 .bingo-approved-actions{position:fixed;z-index:2147481900;right:12px;bottom:calc(96px + env(safe-area-inset-bottom));display:flex;flex-direction:column;align-items:center;gap:13px;color:#fff}
 .bingo-approved-profile{position:relative;width:48px;height:48px}
 .bingo-approved-profile img{width:48px;height:48px;border-radius:50%;object-fit:cover;border:2px solid #ffc928;display:block}
 .bingo-approved-follow{position:absolute;right:-9px;bottom:3px;border:0;background:transparent;color:#fff;font:400 30px/1 Arial;padding:0;text-shadow:0 1px 3px #000;cursor:pointer}
 .bingo-approved-action{display:flex;flex-direction:column;align-items:center;gap:2px;border:0;background:transparent;color:#fff;padding:0;font:800 12px Arial;min-width:46px}
 .bingo-approved-action svg{width:34px;height:34px;display:block}
 .bingo-approved-action .count{display:block;line-height:16px;min-height:16px}
 .bingo-approved-more{font:900 24px/1 Arial;letter-spacing:2px}
 .bingo-approved-meta{position:fixed;z-index:2147481800;left:14px;right:78px;bottom:calc(91px + env(safe-area-inset-bottom));color:#fff;text-shadow:0 1px 3px #000;pointer-events:none}
 .bingo-approved-posted{display:flex;align-items:center;gap:7px;font:800 13px Arial;margin-bottom:5px}
 .bingo-approved-posted img{width:28px;height:28px;border-radius:50%;object-fit:cover;border:1.5px solid #ffc928}
 .bingo-approved-caption{font:500 12px/1.35 Arial;margin:0 0 7px;max-width:90%}
 .bingo-approved-sound{display:inline-flex;align-items:center;gap:4px;font:600 9px/1.2 Arial;background:#0007;border-radius:8px;padding:3px 6px}
 .bingo-approved-views{display:flex;align-items:center;gap:4px;font:600 9px/1.2 Arial;margin-top:3px}
 .bingo-approved-nav{position:fixed;z-index:2147482100;left:0;right:0;bottom:0;height:calc(72px + env(safe-area-inset-bottom));padding-bottom:env(safe-area-inset-bottom);background:#05080d;display:grid;grid-template-columns:repeat(5,1fr);align-items:center;border-top:1px solid #151a22}
 .bingo-approved-nav button{border:0;background:transparent;color:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3px;font:600 10px Arial;height:68px;padding:0}
 .bingo-approved-nav button svg{width:25px;height:25px}
 .bingo-approved-nav button.active{color:#ffc928}
 .bingo-approved-nav .bingo-approved-create{font:300 40px/1 Arial;color:#fff}
 body.bingo-approved-home .bingo-feed-clean-avatar{display:none!important}
}
`;document.head.appendChild(css);

let soundOn=true,lastVideo=null;
function home(){return !window.state||String(window.state.view||'home')==='home'}
function firstVisibleVideo(){
 const vs=[...document.querySelectorAll('#auto-arcade-widget .aa360-feed video.aa360-video')];
 return vs.find(v=>{const r=v.getBoundingClientRect();return r.bottom>innerHeight*.25&&r.top<innerHeight*.75})||vs[0]||null;
}
function clickExisting(words){
 const els=[...document.querySelectorAll('button,a')].filter(e=>!e.closest('.bingo-approved-ui'));
 const hit=els.find(e=>words.some(w=>(e.textContent||'').trim().toLowerCase().includes(w)));
 if(hit){hit.click();return true}return false;
}
function numNear(words,fallback){
 const els=[...document.querySelectorAll('button,a,span,div')].filter(e=>words.some(w=>(e.textContent||'').toLowerCase().includes(w)));
 for(const e of els){const m=(e.textContent||'').match(/\b\d+(?:\.\d+)?[km]?\b/i);if(m)return m[0]}
 return fallback;
}
function findAvatar(){
 const imgs=[...document.querySelectorAll('#auto-arcade-widget .aa360-feed img')].filter(i=>i.offsetWidth>0&&i.offsetHeight>0);
 return imgs.find(i=>/profile|avatar|user/i.test((i.alt||'')+' '+(i.className||'')))||imgs.find(i=>i.naturalWidth&&i.naturalHeight)||null;
}
function findPoster(){
 const txt=[...document.querySelectorAll('#auto-arcade-widget .aa360-feed *')].map(e=>(e.textContent||'').trim()).find(t=>/^posted by /i.test(t));
 return txt?txt.replace(/^posted by\s*/i,'').split('\n')[0].trim():'';
}
function ensureUI(){
 if(!home()){document.body.classList.remove('bingo-approved-home');document.querySelectorAll('.bingo-approved-ui').forEach(x=>x.remove());return}
 document.body.classList.add('bingo-approved-home');
 if(document.querySelector('.bingo-approved-top'))return;
 const top=document.createElement('div');top.className='bingo-approved-ui bingo-approved-top';
 top.innerHTML='<div class="bingo-approved-logo">Bingo</div><div class="bingo-approved-filters"><button class="bingo-approved-filter active">All</button><button class="bingo-approved-filter">Following</button><button class="bingo-approved-filter">Nearby</button></div><button class="bingo-approved-speaker" aria-label="Sound on">'+ICON.speakerOn+'</button>';
 document.body.appendChild(top);
 top.querySelectorAll('.bingo-approved-filter').forEach(b=>b.onclick=()=>{top.querySelectorAll('.bingo-approved-filter').forEach(x=>x.classList.remove('active'));b.classList.add('active');if(b.textContent!=='All')clickExisting([b.textContent.toLowerCase()])});
 top.querySelector('.bingo-approved-speaker').onclick=()=>{soundOn=!soundOn;const b=top.querySelector('.bingo-approved-speaker');b.innerHTML=soundOn?ICON.speakerOn:ICON.speakerOff;b.setAttribute('aria-label',soundOn?'Sound on':'Sound off');document.querySelectorAll('video').forEach(v=>v.muted=!soundOn);if(soundOn){const v=firstVisibleVideo();if(v)v.play().catch(()=>{})}};
 const nav=document.createElement('nav');nav.className='bingo-approved-ui bingo-approved-nav';
 nav.innerHTML='<button class="active" data-go="home">'+ICON.home+'<span>Home</span></button><button data-go="live">'+ICON.live+'<span>Live</span></button><button class="bingo-approved-create" data-go="post">+</button><button data-go="marketplace">'+ICON.market+'<span>Marketplace</span></button><button data-go="messages">'+ICON.messages+'<span>Messages</span></button>';
 document.body.appendChild(nav);
 nav.querySelectorAll('[data-go]').forEach(b=>b.onclick=()=>clickExisting([b.dataset.go,b.textContent.trim().toLowerCase()]));
 const actions=document.createElement('aside');actions.className='bingo-approved-ui bingo-approved-actions';
 actions.innerHTML='<div class="bingo-approved-profile"><img alt="Profile"><button class="bingo-approved-follow" aria-label="Add">+</button></div><button class="bingo-approved-action crown">'+ICON.crown+'<span class="count">0</span></button><button class="bingo-approved-action comments">'+ICON.comment+'<span class="count">0</span></button><button class="bingo-approved-action share">'+ICON.share+'<span class="count">0</span></button><button class="bingo-approved-action bingo-approved-more">•••</button>';
 document.body.appendChild(actions);
 actions.querySelector('.bingo-approved-follow').onclick=()=>clickExisting(['follow','add']);
 actions.querySelector('.crown').onclick=()=>clickExisting(['crown']);
 actions.querySelector('.comments').onclick=()=>clickExisting(['comment']);
 actions.querySelector('.share').onclick=()=>clickExisting(['share']);
 actions.querySelector('.bingo-approved-more').onclick=()=>clickExisting(['more','report']);
 const meta=document.createElement('div');meta.className='bingo-approved-ui bingo-approved-meta';
 meta.innerHTML='<div class="bingo-approved-posted"><img alt=""><span></span></div><p class="bingo-approved-caption"></p><div class="bingo-approved-sound">♫ Original Sound</div><div class="bingo-approved-views">◉ <span>0 views</span></div>';
 document.body.appendChild(meta);
 refresh();
}
function refresh(){
 if(!home())return;
 const a=findAvatar(),src=a&&a.src;
 document.querySelectorAll('.bingo-approved-profile img,.bingo-approved-posted img').forEach(i=>{if(src)i.src=src});
 const poster=findPoster();const ps=document.querySelector('.bingo-approved-posted span');if(ps)ps.textContent=poster?'Posted by '+poster:'Posted';
 const ac=document.querySelector('.bingo-approved-actions');if(ac){ac.querySelector('.crown .count').textContent=numNear(['crown'],'0');ac.querySelector('.comments .count').textContent=numNear(['comment'],'0');ac.querySelector('.share .count').textContent=numNear(['share'],'0')}
 const vv=document.querySelector('.bingo-approved-views span');if(vv)vv.textContent=numNear(['view'],'0')+' views';
 const v=firstVisibleVideo();
 if(v&&v!==lastVideo){lastVideo=v;v.playsInline=true;v.preload='auto';v.muted=!soundOn;try{v.load()}catch(e){};v.play().catch(()=>{v.muted=true;v.play().catch(()=>{})})}
}
let pending=false;function schedule(){if(pending)return;pending=true;setTimeout(()=>{pending=false;ensureUI();refresh()},120)}
new MutationObserver(schedule).observe(document.documentElement,{childList:true,subtree:true});
document.addEventListener('pointerdown',()=>{if(soundOn){const v=firstVisibleVideo();if(v){v.muted=false;v.play().catch(()=>{})}}},{passive:true});
window.addEventListener('pageshow',schedule);window.addEventListener('resize',schedule);
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',schedule,{once:true});else schedule();
})();

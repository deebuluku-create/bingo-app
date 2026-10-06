/* Bingo Home Feed surgical UI override — external, master HTML untouched */
(function(){
'use strict';
if(window.__bingoFeedSurgicalV1) return; window.__bingoFeedSurgicalV1=true;
/* The Home author avatar and its styles are rendered by the master (aaMixedFeedTopicCardHTML). */

const norm=s=>(s||'').replace(/\s+/g,' ').trim().toLowerCase();
/* Matches exactly what the old whole-document scan matched (a button/a/span/div whose entire text is
   one of these labels), but found by climbing from short text nodes inside the changed subtree instead
   of reading textContent of every div in the document on each DOM change. */
const HIDE_SELF=new Set(['all kenya','following','videos','photos']);
const MAX_LABEL=9;
function shortTextOwners(scope,cb){
  const ok=new Set(),big=new Set();
  const visit=t=>{const s=norm(t.nodeValue);if(!s||s.length>MAX_LABEL)return;
    for(let el=t.parentElement;el&&el!==document.documentElement;el=el.parentElement){
      if(ok.has(el)||big.has(el))break;
      const txt=norm(el.textContent);if(txt.length>MAX_LABEL){big.add(el);break}
      ok.add(el);if(/^(BUTTON|A|SPAN|DIV)$/.test(el.tagName))cb(el,txt);
    }};
  if(scope.nodeType===3){visit(scope);return}
  const w=document.createTreeWalker(scope,NodeFilter.SHOW_TEXT);while(w.nextNode())visit(w.currentNode);
}
function hideLegacy(scope){
  shortTextOwners(scope,(e,txt)=>{
    if(HIDE_SELF.has(txt))e.style.display='none';
    else if(txt==='post')(e.closest('button,a')||e).style.display='none';
    else if(e.tagName==='BUTTON'&&(txt==='▶'||txt==='play')&&!e.querySelector('video,img,picture,source'))e.style.display='none';
  });
}
function run(scope){hideLegacy(scope);}
/* Work only on what was inserted since the last pass (coalesced into one pass per 300ms), never a
   rescan of the whole document: idle DOM ticks no longer cost a full-document text read. */
const pending=new Set();let runPending=false;
function scheduleRun(records){
 for(const m of records)for(const n of m.addedNodes)if(n.nodeType===1||n.nodeType===3)pending.add(n);
 if(runPending||!pending.size)return; runPending=true;
 setTimeout(()=>{
   runPending=false;
   let scopes=[...pending].filter(n=>n.isConnected);pending.clear();
   if(scopes.length>300)scopes=[document.body];
   else scopes=scopes.filter(n=>!scopes.some(o=>o!==n&&o.nodeType===1&&o.contains(n)));
   scopes.forEach(run);
 },300);
}
new MutationObserver(scheduleRun).observe(document.documentElement,{childList:true,subtree:true});
run(document.body||document.documentElement);
})();

/* Canonical Home guard: never show the retired 360View empty landing.
   Home remains the swipe feed surface and re-renders when async post data arrives. */
(function installBingoHomeFeedGuard(){
 function install(){
   if(typeof window.homeHTML!=='function'||window.__bingoHomeFeedGuard)return false;
   window.__bingoHomeFeedGuard=true;
   const original=window.homeHTML;
   window.homeHTML=function(boosted,rows,all,pages){
     let items=[]; try{items=typeof window.aaMixedFeedItems==='function'?window.aaMixedFeedItems():[]}catch(e){}
     if(items&&items.length) return original.apply(this,arguments);
     return '<section class="aa360-shell"><div class="aa360-feed" id="bingoHomeFeedWaiting" aria-live="polite"></div></section>';
   };
   let tries=0;
   const timer=setInterval(function(){
     tries++;
     try{
       /* A painted Home item is authoritative. Never request another Home render from this guard:
          logo/comment/profile animations mutate descendants of the live card and must not cause
          the underlying post/video node to be replaced. */
       if(document.querySelector('#auto-arcade-widget .aa360-feed .aa360-item')){clearInterval(timer);return}
       /* The guard gets exactly one recovery render, and only while the explicit waiting shell is
          still mounted and real feed data has arrived. This prevents old/new/blank feed flip-flop. */
       if(document.getElementById('bingoHomeFeedWaiting')&&window.state&&state.view==='home'&&typeof window.aaMixedFeedItems==='function'&&aaMixedFeedItems().length){
         clearInterval(timer);
         if(!window.__bingoHomeWaitingRenderIssued){
           window.__bingoHomeWaitingRenderIssued=true;
           if(typeof window.aaRequestRender==='function')aaRequestRender(); else if(typeof window.render==='function')render();
           setTimeout(function(){window.__bingoHomeWaitingRenderIssued=false},1200);
         }
       } else if(tries>=40) clearInterval(timer);
     }catch(e){if(tries>=40)clearInterval(timer)}
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


/* Bingo Home comments UX repair — 2026-10-04.
   Surgical overlay only: preserves native comment/crown persistence and all unrelated feed wiring.
   Rotating comments and the Home Comments sheet are provided by the master's canonical
   "bingo-rotating-comments" module (real stored comments, one lane, real avatars), so this file
   no longer runs a second rotator; it keeps only the duplicate post-text clean-up. */
(function bingoHomeCommentsUxRepair(){
'use strict';
if(window.__bingoHomeCommentsUxRepair)return; window.__bingoHomeCommentsUxRepair=true;
const css=document.createElement('style');
css.textContent=`
.aa360-item .bingo-duplicate-post-text{display:none!important}
`;document.head.appendChild(css);

const txt=e=>(e?.textContent||'').replace(/\s+/g,' ').trim();
function dedupePostText(root){
  (root||document).querySelectorAll?.('.aa360-item').forEach(card=>{
    /* One canonical post text per Home card. The animated/floating presentation and the
       permanent caption are styling alternatives, never two copies of the same post.
       Comment lanes/sheets remain excluded because their text is user discussion. */
    const pool=[...card.querySelectorAll('p,.caption,.post-text,.aa360-caption,.aa360-text,[data-post-text],.aa360-title,.aa360-body,[data-post-title],[data-post-body]')]
      .filter(e=>e.offsetParent!==null && txt(e) && txt(e).length<=1500 && !e.closest('.bingo-rc-lane,.bingo-cs-host') && !/^♪?\\s*original sound/i.test(txt(e)));
    const groups=new Map();
    for(const e of pool){
      const k=txt(e).toLowerCase();
      if(!groups.has(k))groups.set(k,[]);
      groups.get(k).push(e);
    }
    groups.forEach(group=>{
      if(group.length<2)return;
      /* Prefer the stable caption/post-text node as canonical. A floating/hero copy is hidden.
         If markup has no semantic clue, retain the last (caption-area) copy visible. */
      const score=e=>{
        const s=((e.className||'')+' '+(e.getAttribute('data-post-text')||'')).toLowerCase();
        return /caption|post-text|aa360-text/.test(s)&&!/hero|float|animat|overlay/.test(s)?3:
               /hero|float|animat|overlay/.test(s)?0:1;
      };
      const keep=group.slice().sort((a,b)=>score(b)-score(a))[0]||group[group.length-1];
      group.forEach(e=>{if(e!==keep)e.classList.add('bingo-duplicate-post-text');else e.classList.remove('bingo-duplicate-post-text')});
    });
  });
}
let q=false;new MutationObserver(()=>{if(q)return;q=true;setTimeout(()=>{q=false;dedupePostText(document)},220)})
 .observe(document.documentElement,{childList:true,subtree:true});
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>dedupePostText(document),{once:true});else dedupePostText(document);
})();

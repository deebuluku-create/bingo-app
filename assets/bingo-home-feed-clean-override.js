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
new MutationObserver(run).observe(document.documentElement,{childList:true,subtree:true});
run();
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
       if(window.state&&state.view==='home'&&typeof window.aaMixedFeedItems==='function'&&aaMixedFeedItems().length){
         clearInterval(timer); if(typeof window.render==='function')render();
       } else if(tries>=40) clearInterval(timer);
     }catch(e){if(tries>=40)clearInterval(timer)}
   },250);
   return true;
 }
 if(!install()){
   let n=0,t=setInterval(()=>{if(install()||++n>40)clearInterval(t)},100);
 }
})();
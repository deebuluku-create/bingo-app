/* Bingo Home legacy-demo exclusion + canonical avatar lock — 2026-10-05.
   Surgical scope only: Home feed. No master rewrite, no marketplace data deletion,
   no routing/payment/upload/comment/crown/share changes. */
(function(){'use strict';
if(window.__bingoHomeLegacyAvatarLock)return;window.__bingoHomeLegacyAvatarLock=1;
const ROOT='#auto-arcade-widget';
/* Retire the Home Feed presentation only. Preserve Home functions, posts, media,
   Supabase and all other pages for future development.
   Route Home entry to the EXISTING Bingo Wall using its own navigation control. */
(function retireHomeLanding(){
 var working=false, lastAttempt=0;
 function home(){try{return window.state&&state.view==='home'}catch(_){return false}}
 function wallControl(){
  var scope=document.getElementById('auto-arcade-widget')||document;
  var candidates=scope.querySelectorAll('button,a,[role="button"],[onclick]');
  for(var i=0;i<candidates.length;i++){
   var el=candidates[i];
   var t=(el.getAttribute('aria-label')||el.getAttribute('title')||el.textContent||'').replace(/\\s+/g,' ').trim().toLowerCase();
   if(t==='bingo wall'||t==='wall'||t==='topics'||t==='bingo topics')return el;
  }
  return null;
 }
 function redirect(){
  if(!home()||working||Date.now()-lastAttempt<350)return;
  lastAttempt=Date.now();working=true;
  try{
   var el=wallControl();
   if(el)el.click();
   /* A missing/hidden control must not send users back to the retired Home.
      This changes only the frontend view, not stored posts or profiles. */
   if(home()&&window.state){
    state.view='topics';
    if(typeof window.aaRequestRender==='function')window.aaRequestRender();
    else if(typeof window.render==='function')window.render();
   }
  }catch(_){}
  working=false;
 }
 function schedule(){
  if(!home())return;
  if(typeof window.requestAnimationFrame==='function')requestAnimationFrame(redirect);
  else setTimeout(redirect,0);
 }
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',schedule,{once:true});
 else schedule();
 var queued=false;
 new MutationObserver(function(){
  if(queued||!home())return;
  queued=true;setTimeout(function(){queued=false;schedule()},140);
 }).observe(document.documentElement,{childList:true,subtree:true});
 document.addEventListener('click',function(ev){
  var t=ev.target.closest&&ev.target.closest('button,a,[role="button"]');
  if(!t)return;
  var label=(t.getAttribute('aria-label')||t.textContent||'').replace(/\\s+/g,' ').trim().toLowerCase();
  if(label==='home')setTimeout(schedule,80);
 },false);
})();;

const norm=s=>(s||'').replace(/\s+/g,' ').trim().toLowerCase();
function home(){try{return !!(window.state&&state.view==='home')}catch(_){return false}}

/* 1) Retired demo/360 presentation must never be a Home feed item.
   Filter only unmistakable legacy demo signatures. Real Marketplace records pass through. */
function legacyDemo(x){
 if(!x||typeof x!=='object')return false;
 const blob=norm([
   x.title,x.name,x.seller_name,x.description,x.caption,x.text,x.location,
   x.badge,x.type,x.kind,x.source,x.subtitle
 ].filter(Boolean).join(' '));
 return blob.includes('modern bingo 360view preview') ||
   (blob.includes('bingo seller')&&blob.includes('toyota land cruiser prado tx'));
}
function installFeedFilter(){
 if(typeof window.aaMixedFeedItems!=='function'||window.aaMixedFeedItems.__bingoLegacyFiltered)return false;
 const original=window.aaMixedFeedItems;
 function filtered(){
   const rows=original.apply(this,arguments);
   return Array.isArray(rows)?rows.filter(x=>!legacyDemo(x)):rows;
 }
 filtered.__bingoLegacyFiltered=true;filtered.__bingoOriginal=original;
 window.aaMixedFeedItems=filtered;return true;
}

/* 2) One stable avatar DOM node/source per Home post. The existing clean override
   creates .bingo-feed-clean-avatar. Once first resolved for that rendered post,
   later legacy hydration is not allowed to replace/flicker it. */
/* Keep one avatar element per post, but never freeze its initial URL.
   Async profile hydration must be allowed to replace a demo/placeholder avatar.
   Restrict selection to the author area: never touch actual post media. */
function lockAvatars(){
 if(!home())return;
 document.querySelectorAll(ROOT+' .aa360-item').forEach(card=>{
   const avs=[...card.querySelectorAll('.bingo-feed-clean-avatar')];
   if(!avs.length)return;
   const keeper=avs[0];
   avs.slice(1).forEach(a=>a.remove());
   /* Do not write keeper.src: the master renderer owns profile hydration. */
   [...card.querySelectorAll('a,button')].forEach(link=>{
     if(norm(link.textContent).includes('view profile')){
       const legacy=link.parentElement;
       if(legacy&&!legacy.contains(keeper))legacy.style.setProperty('display','none','important');
     }
   });
 });
}
let tries=0,t=setInterval(()=>{tries++;const ok=installFeedFilter();if(ok||tries>80)clearInterval(t)},100);
let q=0;new MutationObserver(ms=>{
 if(!home())return;
 let relevant=false;
 for(const m of ms){
   if(m.type==='childList'&&m.addedNodes.length){relevant=true;break}
   if(m.type==='attributes'&&m.target?.classList?.contains('bingo-feed-clean-avatar')){relevant=true;break}
 }
 if(!relevant)return;clearTimeout(q);q=setTimeout(lockAvatars,120);
}).observe(document.documentElement,{childList:true,subtree:true,attributes:true,attributeFilter:['src']});
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',lockAvatars,{once:true});else lockAvatars();
})();
/* Bingo Home legacy-demo exclusion + canonical avatar lock — 2026-10-05.
   Surgical scope only: Home feed. No master rewrite, no marketplace data deletion,
   no routing/payment/upload/comment/crown/share changes. */
(function(){'use strict';
if(window.__bingoHomeLegacyAvatarLock)return;window.__bingoHomeLegacyAvatarLock=1;
const ROOT='#auto-arcade-widget';
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
const avatarSrc=new Map();
function keyFor(card,index){
 return card.getAttribute('data-post-id')||card.dataset?.id||card.id||('home-card-'+index);
}
function lockAvatars(){
 if(!home())return;
 document.querySelectorAll(ROOT+' .aa360-item').forEach((card,index)=>{
   const key=keyFor(card,index);
   const avs=[...card.querySelectorAll('.bingo-feed-clean-avatar')];
   if(!avs.length)return;
   let keeper=avs[0];
   avs.slice(1).forEach(a=>a.remove());
   const src=keeper.currentSrc||keeper.src||'';
   if(!avatarSrc.has(key)&&src)avatarSrc.set(key,src);
   const canonical=avatarSrc.get(key);
   if(canonical&&keeper.src!==canonical)keeper.src=canonical;
   keeper.dataset.bingoCanonicalAvatar=key;
   /* Legacy author cards are presentation duplicates only. Do not remove data. */
   /* Restore original separation: a feed/listing may link to a profile, but must never
      render the full profile presentation inside the listing. Scope is the duplicate identity
      wrapper immediately owning the explicit View profile control; profile pages and Wall are untouched. */
   [...card.querySelectorAll('a,button')].forEach(link=>{
     if(norm(link.textContent).includes('view profile')){
       const legacy=link.parentElement;
       if(legacy&&!legacy.contains(keeper))legacy.style.setProperty('display','none','important');
     }
   });
   /* Some business/listing cards omit the words "View profile" and expose the same legacy identity
      as a large linked portrait. Hide only that duplicate when the canonical compact avatar exists. */
   [...card.querySelectorAll('a[href*="profile"],button[data-profile-id],button[aria-label*="profile" i]')].forEach(link=>{
     if(link.contains(keeper))return;
     const imgs=[...link.querySelectorAll('img')];
     if(!imgs.length)return;
     const box=link.getBoundingClientRect();
     if(box.width>180&&box.height>180)link.style.setProperty('display','none','important');
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
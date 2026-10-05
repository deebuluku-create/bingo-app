/* Bingo rich-share canonicalizer — 2026-10-05. Surgical share layer only. */
(function(){'use strict';if(window.__bingoRichShare)return;window.__bingoRichShare=1;
const ORIGIN='https://preview.bingo-app.co.ke';
function cleanUrl(raw){
 try{
  const u=new URL(raw||location.href,location.href);
  if(/(^|\.)autoacade\.com$/i.test(u.hostname)||/(^|\.)bingo-app\.co\.ke$/i.test(u.hostname)){
   return ORIGIN+u.pathname+u.search+u.hash;
  }
  return u.href;
 }catch(_){return ORIGIN+'/'}
}
function context(el){
 const card=el&&el.closest&&el.closest('[data-post-id],.aa360-item,article,.post,.feed-item,[data-listing-id]');if(!card)return null;
 const title=(card.querySelector('h1,h2,h3,[data-title],.title,.post-title')?.textContent||'').trim();
 const desc=(card.querySelector('[data-description],.description,.post-body,.caption,p')?.textContent||'').trim();
 const media=card.querySelector('video,img:not(.bingo-feed-clean-avatar)');
 const id=card.getAttribute('data-post-id')||card.getAttribute('data-listing-id')||'';
 let url=cleanUrl(location.href);
 if(id&&!/[#?].*(post|topic|listing)/i.test(url))url=ORIGIN+'/#post-'+encodeURIComponent(id);
 return {title:title||'Bingo App Kenya',text:(desc||title||'View this on Bingo App Kenya').slice(0,240),url,media};
}
const nativeShare=navigator.share&&navigator.share.bind(navigator);
if(nativeShare)navigator.share=async function(data){
 data=data||{};const c=context(document.activeElement);
 return nativeShare({title:data.title||(c&&c.title)||'Bingo App Kenya',text:data.text||(c&&c.text)||'View on Bingo App Kenya',url:cleanUrl(data.url||(c&&c.url)||location.href),files:data.files});
};
document.addEventListener('click',function(e){
 const a=e.target.closest&&e.target.closest('a[href]');
 if(a&&/autoacade\.com/i.test(a.href))a.href=cleanUrl(a.href);
},true);
})();
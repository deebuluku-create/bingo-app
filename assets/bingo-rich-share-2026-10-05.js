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
async function previewFile(media){
 if(!media)return null;
 let src=media.tagName==='VIDEO'?(media.poster||''):(media.currentSrc||media.src||'');
 if(!src||/^data:/i.test(src))return null;
 try{
  const r=await fetch(src,{mode:'cors',credentials:'omit'});if(!r.ok)return null;
  const b=await r.blob();if(!/^image\//i.test(b.type)||b.size>12*1024*1024)return null;
  const ext=(b.type.split('/')[1]||'jpg').replace('jpeg','jpg').replace(/[^a-z0-9]/gi,'')||'jpg';
  return new File([b],'bingo-post-preview.'+ext,{type:b.type});
 }catch(_){return null}
}
const nativeShare=navigator.share&&navigator.share.bind(navigator);
if(nativeShare)navigator.share=async function(data){
 data=data||{};const c=context(document.activeElement);
 const payload={title:data.title||(c&&c.title)||'Bingo App Kenya',text:data.text||(c&&c.text)||'View on Bingo App Kenya',url:cleanUrl(data.url||(c&&c.url)||location.href)};
 if(data.files&&data.files.length)payload.files=data.files;
 else if(c&&c.media&&navigator.canShare){
  const file=await previewFile(c.media);
  if(file){const trial=Object.assign({},payload,{files:[file]});try{if(navigator.canShare(trial))payload.files=[file]}catch(_){}}
 }
 return nativeShare(payload);
};
document.addEventListener('click',function(e){
 const a=e.target.closest&&e.target.closest('a[href]');
 if(a&&/autoacade\.com/i.test(a.href))a.href=cleanUrl(a.href);
},true);
})();
/* Bingo Topic composer cleanup — scoped to .aa-composer-card only.
   Keeps the existing post, media, sound and formatting handlers; changes presentation only. */
(function(){'use strict';if(window.BingoComposerCleanup)return;
const css=document.createElement('style');css.textContent=`
.aa-composer-card .bingo-clean-textwrap{position:relative}
.aa-composer-card .bingo-clean-camera{position:absolute;right:48px;bottom:9px;width:34px;height:34px;border:1px solid var(--gold,#f5c542);border-radius:50%;background:#0b1728;color:#fff;display:grid;place-items:center;cursor:pointer;z-index:3;padding:0}
.aa-composer-card .bingo-clean-camera svg{width:18px;height:18px}
.aa-composer-card .bingo-clean-textwrap textarea{padding-right:92px!important}
.aa-composer-card .bingo-clean-format{position:absolute;right:10px;bottom:9px;width:34px;height:34px;border:1px solid var(--gold,#f5c542);border-radius:50%;background:#0b1728;color:#fff;display:grid;place-items:center;cursor:pointer;z-index:3;padding:0;font-size:22px;line-height:1}
.aa-composer-card>.aa-media-camera-box{display:none!important}
.aa-composer-card .bingo-sound-composer{display:none!important}
.aa-composer-card .bingo-clean-source-control{display:none!important}
.aa-composer-card .bingo-sound-composer .bsc-actions{display:none!important}
.aa-composer-card .bingo-sound-composer .bsc-sub{display:flex!important;align-items:center;gap:10px;flex-wrap:wrap}
.aa-composer-card .bingo-sound-composer .bsc-sub button{border:0!important;background:transparent!important;box-shadow:none!important;padding:2px 0!important;text-decoration:none;color:var(--gold,#f5c542)!important}
.aa-composer-card .bingo-sound-more{position:relative;margin-left:auto}
.aa-composer-card .bingo-sound-more>button{border:0;background:transparent;color:#fff;font-size:20px;padding:2px 8px;cursor:pointer}
.aa-composer-card .bingo-sound-menu{position:absolute;right:0;top:28px;z-index:20;min-width:150px;background:#071323;border:1px solid #56647a;border-radius:10px;padding:6px;box-shadow:0 10px 24px #0008}
.aa-composer-card .bingo-sound-menu[hidden]{display:none}
.aa-composer-card .bingo-sound-menu button{display:block;width:100%;text-align:left;border:0;background:transparent;color:#fff;padding:9px;border-radius:7px}
.aa-composer-card .bingo-sound-menu button:hover{background:#ffffff12}
`;document.head.appendChild(css);
function cameraSvg(){return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 8h3l1.5-2h7L17 8h3a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1z"/><circle cx="12" cy="13" r="3.4"/></svg>'}
function clean(card){
 if(!card||card.dataset.bingoCleanComposer==='1')return;
 /* The master composer now renders the single text surface itself (camera + ⋮ inside it, the
    50-font picker and sound actions in its ⋮ menu). Only the approved Awards crown icon is applied here. */
 if(card.querySelector('.aa-composer-surface')){
   const aw=[...card.querySelectorAll('button')].find(b=>(b.textContent||'').includes('Awards'));
   if(aw)aw.innerHTML=aw.innerHTML.replace('🏆','👑');
   const nt=[...card.querySelectorAll('.notice')].find(n=>(n.textContent||'').includes('Bingo Impact Awards'));
   if(nt)nt.innerHTML=nt.innerHTML.replace('🏆','👑');
   card.dataset.bingoCleanComposer='1';return;
 }
 const ta=card.querySelector('#topicBody'),grid=ta?.closest('.form-grid'),input=card.querySelector('#topicMedia');
 if(ta&&grid&&input&&!grid.querySelector('.bingo-clean-camera')){
   grid.classList.add('bingo-clean-textwrap');
   const sourceButtons=[...card.querySelectorAll('button')];
   const originalCamera=sourceButtons.find(x=>x!==input&&(/photo|video|media|camera/i.test((x.title||'')+' '+(x.getAttribute('aria-label')||''))));
   const originalFormat=sourceButtons.find(x=>/^Aa$/i.test((x.textContent||'').trim())||/font|format|color/i.test((x.title||'')+' '+(x.getAttribute('aria-label')||'')));
   if(originalCamera)originalCamera.classList.add('bingo-clean-source-control');
   if(originalFormat)originalFormat.classList.add('bingo-clean-source-control');
   const b=document.createElement('button');b.type='button';b.className='bingo-clean-camera';b.title='Add photo or video';b.setAttribute('aria-label','Add photo or video');b.innerHTML=cameraSvg();b.onclick=()=>{if(!b.disabled)input.click()};grid.appendChild(b);
   const fmt=document.createElement('button');fmt.type='button';fmt.className='bingo-clean-format';fmt.title='Fonts and colors';fmt.setAttribute('aria-label','Fonts and colors');fmt.textContent='⋮';fmt.onclick=()=>{if(originalFormat){originalFormat.click();return;} const fallback=[...card.querySelectorAll('button')].find(x=>/font|format|color/i.test((x.title||'')+' '+(x.getAttribute('aria-label')||'')));if(fallback)fallback.click();};grid.appendChild(fmt);
 }
 const award=[...card.querySelectorAll('button')].find(b=>(b.textContent||'').includes('Awards'));
 if(award)award.innerHTML=award.innerHTML.replace('🏆','👑');
 const notice=[...card.querySelectorAll('.notice')].find(n=>(n.textContent||'').includes('Bingo Impact Awards'));
 if(notice)notice.innerHTML=notice.innerHTML.replace('🏆','👑');
 const sound=card.querySelector('.bingo-sound-composer.is-selected');
 if(sound&&!sound.querySelector('.bingo-sound-more')){
   const sub=sound.querySelector('.bsc-sub')||sound;
   const more=document.createElement('span');more.className='bingo-sound-more';
   more.innerHTML='<button type="button" aria-label="More sound options" title="More sound options">⋮</button><span class="bingo-sound-menu" hidden><button type="button" data-a="create">Create Video</button><button type="button" data-a="change">Change sound</button><button type="button" data-a="remove">Remove sound</button></span>';
   const menu=more.querySelector('.bingo-sound-menu');more.firstElementChild.onclick=e=>{e.stopPropagation();menu.hidden=!menu.hidden};
   more.querySelector('[data-a="create"]').onclick=()=>{menu.hidden=true;window.BingoSounds?.create?.()};
   more.querySelector('[data-a="change"]').onclick=()=>{menu.hidden=true;window.BingoSounds?.library?.()};
   more.querySelector('[data-a="remove"]').onclick=()=>{menu.hidden=true;window.BingoSounds?.clear?.()};
   sub.appendChild(more);
 }
 card.dataset.bingoCleanComposer='1';
}
function scan(root=document){if(root.matches?.('.aa-composer-card'))clean(root);root.querySelectorAll?.('.aa-composer-card').forEach(clean)}
const mo=new MutationObserver(ms=>ms.forEach(m=>m.addedNodes.forEach(n=>{if(n.nodeType===1)scan(n)})));mo.observe(document.documentElement,{childList:true,subtree:true});scan();

/* Stage 1 stylish-post entitlement: advanced post layouts/fonts/colors unlock only after
   the signed-in member has received at least 10 paid crowns. Basic posting/media stays available.
   Uses the persisted paid-crown ledger; failure to verify never grants the premium tools. */
const STAGE1_CROWNS=10;
let stage1Cache={uid:null,count:0,ok:false,at:0};
async function stage1(){
 try{
  const s=(await window.supabase?.auth?.getSession?.())?.data?.session;if(!s)return stage1Cache={uid:null,count:0,ok:false,at:Date.now()};
  if(stage1Cache.uid===s.user.id&&Date.now()-stage1Cache.at<30000)return stage1Cache;
  const {count,error}=await window.supabase.from('bingo_crown_purchases').select('id',{count:'exact',head:true})
    .eq('recipient_id',s.user.id).eq('payment_status','paid');
  if(error)throw error;
  return stage1Cache={uid:s.user.id,count:Number(count||0),ok:Number(count||0)>=STAGE1_CROWNS,at:Date.now()};
 }catch(_){return stage1Cache={uid:null,count:0,ok:false,at:Date.now()}}
}
function isStyleControl(b){
 const s=((b?.textContent||'')+' '+(b?.title||'')+' '+(b?.getAttribute?.('aria-label')||'')).toLowerCase();
 return /font|format|color|style|layout/.test(s)||/^\s*aa\s*$/i.test(b?.textContent||'');
}
document.addEventListener('click',async e=>{
 const b=e.target.closest?.('.aa-composer-card button,.aa-composer-card [role="button"]');if(!b||!isStyleControl(b))return;
 const ent=await stage1();if(ent.ok)return;
 e.preventDefault();e.stopImmediatePropagation();
 const need=Math.max(0,STAGE1_CROWNS-ent.count);
 alert('Stage 1 feature: receive 10 crowns to unlock stylish post layouts, fonts and colors. '+need+' more crown'+(need===1?'':'s')+' needed.');
},true);
window.BingoStage1PostStyles={required:STAGE1_CROWNS,status:stage1};

window.BingoComposerCleanup={scan};
})();
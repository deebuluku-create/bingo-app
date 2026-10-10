/* Bingo paid crowns — isolated addon. No mother HTML edits. */
(function(){'use strict';if(window.BingoPaidCrowns)return;
const crownSvg=(kind)=>{const pal={bronze:['#4b1d08','#ff8a32','#8b3d12'],silver:['#4b5563','#ffffff','#9ca3af'],gold:['#8a5200','#ffd84a','#f59e0b']}[kind]||['#8a5200','#ffd84a','#f59e0b'];return '<svg class="bc-crown3d '+kind+'" viewBox="0 0 120 92" aria-hidden="true"><defs><linearGradient id="bcg-'+kind+'" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="'+pal[1]+'"/><stop offset=".48" stop-color="'+pal[2]+'"/><stop offset="1" stop-color="'+pal[0]+'"/></linearGradient><filter id="bcs-'+kind+'"><feDropShadow dx="0" dy="3" stdDeviation="3" flood-color="'+pal[1]+'" flood-opacity=".42"/></filter></defs><path filter="url(#bcs-'+kind+')" fill="url(#bcg-'+kind+')" stroke="'+pal[1]+'" stroke-width="2" d="M16 70 9 27l26 20L60 10l25 37 26-20-7 43z"/><path fill="'+pal[0]+'" opacity=".78" d="M17 70h86l-5 13H22z"/><circle cx="9" cy="27" r="6" fill="'+pal[1]+'"/><circle cx="60" cy="10" r="6" fill="'+pal[1]+'"/><circle cx="111" cy="27" r="6" fill="'+pal[1]+'"/><path d="M26 62h68" stroke="#fff" stroke-opacity=".65" stroke-width="3"/></svg>'};const tiers={bronze:{label:'Bronze Crown',amount:5,icon:crownSvg('bronze')},silver:{label:'Silver Crown',amount:25,icon:crownSvg('silver')},gold:{label:'Gold Crown',amount:50,icon:crownSvg('gold')}};
const css=document.createElement('style');css.textContent=`
#bingoCrownPay{position:fixed;inset:0;z-index:2147483500;background:#000a;display:grid;place-items:center;padding:18px}#bingoCrownPay[hidden]{display:none}
#bingoCrownPay .bc-card{width:min(420px,100%);background:#071323;color:#fff;border:1px solid #ffc928;border-radius:18px;padding:18px;box-shadow:0 0 30px #000}
#bingoCrownPay .bc-head{display:flex;justify-content:space-between;align-items:center;font-weight:900;font-size:20px}.bc-x{border:0;background:none;color:#fff;font-size:26px}
#bingoCrownPay .bc-tiers{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;margin:16px 0}.bc-tier{border:1px solid #5c6c82;background:#0b192b;color:#fff;border-radius:14px;padding:12px 6px;font-weight:800}
#bingoCrownPay .bc-tier.on{border-color:#ffc928;box-shadow:0 0 10px #ffc92866}.bc-tier span{display:block}.bc-crown3d{display:block;width:58px;height:46px;margin:0 auto 5px;overflow:visible;filter:saturate(1.08)}.bc-tier.on .bc-crown3d{transform:translateY(-1px) scale(1.04);transition:.16s ease}.bc-tier{transition:border-color .16s ease,box-shadow .16s ease,transform .16s ease}.bc-tier:active{transform:scale(.97)}.bc-phone{width:100%;padding:13px;border-radius:12px;border:1px solid #40516a;background:#030b16;color:#fff;font-size:16px}
.bc-pay{width:100%;margin-top:12px;padding:13px;border:1px solid #ffc928;border-radius:14px;background:#ffc928;color:#071323;font-weight:900}.bc-msg{min-height:22px;margin-top:10px;font-size:13px;color:#b9c7d8}`;document.head.appendChild(css);
const host=document.createElement('div');host.id='bingoCrownPay';host.hidden=true;host.innerHTML='<div class="bc-card" role="dialog" aria-modal="true"><div class="bc-head"><span>Give a Crown</span><button class="bc-x" aria-label="Close">×</button></div><div class="bc-tiers"></div><input class="bc-phone" inputmode="tel" placeholder="M-Pesa number e.g. 0712345678"><button class="bc-pay">Send M-Pesa prompt</button><div class="bc-msg"></div></div>';document.body.appendChild(host);
let chosen='bronze',ctx={recipientId:null,topicId:null};
const tiersEl=host.querySelector('.bc-tiers'),msg=host.querySelector('.bc-msg'),pay=host.querySelector('.bc-pay');
function paint(){tiersEl.innerHTML=Object.entries(tiers).map(([k,v])=>'<button class="bc-tier '+(k===chosen?'on':'')+'" data-tier="'+k+'"><span>'+v.icon+'</span>'+v.label+'<br>KSh '+v.amount+'</button>').join('')}
tiersEl.onclick=e=>{const b=e.target.closest('[data-tier]');if(b){chosen=b.dataset.tier;paint()}};host.querySelector('.bc-x').onclick=()=>host.hidden=true;host.onclick=e=>{if(e.target===host)host.hidden=true};
/* In the master app the Supabase CLIENT is window.sb; window.supabase is the CDN library namespace. */
function cl(){return (window.sb&&window.sb.auth)?window.sb:window.supabase}
async function session(){const r=await cl()?.auth?.getSession?.();return r?.data?.session||null}
async function open(recipientId,topicId){const s=await session();if(!s){if(typeof window.requireLogin==='function')return window.requireLogin();alert('Please sign in to give a crown.');return}if(!recipientId||recipientId===s.user.id)return;ctx={recipientId,topicId:topicId||null};chosen='bronze';msg.textContent='Choose Bronze KSh 5, Silver KSh 25 or Gold KSh 50.';paint();host.hidden=false;host.querySelector('.bc-phone').focus()}
async function poll(id){for(let i=0;i<24;i++){await new Promise(r=>setTimeout(r,2500));const {data}=await cl().from('bingo_crown_purchases').select('payment_status').eq('id',id).maybeSingle();if(data?.payment_status==='paid'){msg.textContent='Crown awarded successfully.';setTimeout(()=>host.hidden=true,1200);try{window.aaRequestRender?.()}catch(e){}try{window.aaLoadCrownCounts?.(true)}catch(e){}return}if(['failed','cancelled','expired'].includes(data?.payment_status)){msg.textContent='Payment was not completed.';return}}msg.textContent='Payment is still pending. You can close this window safely.'}
pay.onclick=async()=>{const s=await session();if(!s)return;const phone=host.querySelector('.bc-phone').value.trim();pay.disabled=true;msg.textContent='Sending M-Pesa prompt…';try{const base=String(cl()?.supabaseUrl||window.SUPABASE_URL||'https://ktwkfavryihrfwghsbuo.supabase.co').replace(/\/$/,'');const r=await fetch(base+'/functions/v1/mpesa-crown',{method:'POST',headers:{'Content-Type':'application/json','Authorization':'Bearer '+s.access_token},body:JSON.stringify({recipient_id:ctx.recipientId,topic_id:ctx.topicId,crown_type:chosen,phone})});const j=await r.json();if(!r.ok||!j.ok)throw new Error(j.error||'Unable to start payment');msg.textContent='M-Pesa prompt sent for KSh '+tiers[chosen].amount+'. Complete it on your phone.';poll(j.purchase_id)}catch(e){msg.textContent=e.message||'Unable to send M-Pesa prompt'}finally{pay.disabled=false}};
function idFrom(el,names){for(let p=el;p&&p!==document.body;p=p.parentElement){for(const n of names){const v=p.dataset?.[n];if(v)return v}}return null}
async function recipientFor(el,topic){
 let id=idFrom(el,['recipientId','authorId','userId','profileId'])||window.state?.profileUserId||window.state?.profileId||null;
 if(id)return String(id);
 if(topic&&cl()){try{const {data}=await cl().from('bingo_topics').select('user_id').eq('id',topic).maybeSingle();if(data?.user_id)return String(data.user_id)}catch(e){}}
 return null;
}
document.addEventListener('click',function(e){const b=e.target.closest('button,a');if(!b||b.closest('#bingoCrownPay'))return;if(b.classList.contains('bingo-action-crown'))return;const t=(b.textContent||'').trim().toLowerCase();if(!(t.includes('crown')||t==='♛'||t==='👑'))return;if(t.includes('remove')||t.includes('award')&&t.includes('impact'))return;
 /* Navigation and settings entries that merely mention crowns (e.g. "My Crown Agent Dashboard",
    monetization, wallet) keep their own action; only a give-a-crown control opens checkout. */
 if(/dashboard|agent|monetiz|wallet|earning|withdraw|settings/.test(t)||b.closest('[role="menu"],.aa-desty-drawer-modal,.bp-dots-pop,.bingo-cs-host,.aa-composer-card'))return;
 /* Home post Crown is the existing in-place post reaction. Never hijack it into
    the paid-crown flow: aaTopicLove owns the tap, persists the reaction and
    re-renders its total without changing route. Paid profile crowns remain intact. */
 const homeTopic=b.closest('.aa360-item[data-canon^="topic:"]');
 if(homeTopic)return;
 const topic=idFrom(b,['topicId','postId'])||null;
 e.preventDefault();e.stopImmediatePropagation();
 recipientFor(b,topic).then(recipient=>{if(recipient)open(recipient,topic?String(topic):null)});

},true);
/* Keep the real stored reaction total beside the existing Home Crown label.
   This changes text only; no feed layout, media, routing or other controls. */
function syncHomeCrownCounts(root){
 const scope=root&&root.querySelectorAll?root:document;
 scope.querySelectorAll('.aa360-item[data-canon^="topic:"]').forEach(card=>{
  const id=String(card.dataset.canon||'').slice(6);if(!id)return;
  const b=[...card.querySelectorAll('.aa-icon-action-row button')].find(x=>/crown/i.test(x.getAttribute('title')||x.getAttribute('aria-label')||''));if(!b)return;
  let topic=null;try{topic=(typeof window.aaTopics==='function'?window.aaTopics():window.state?.wallTopics||[]).find(x=>String(x.id)===id)}catch(e){}
  let count=0;try{count=topic&&typeof window.aaTopicLoveCount==='function'?Number(window.aaTopicLoveCount(topic)||0):0}catch(e){}
  /* Write only when the text actually differs: an unconditional write is itself a DOM change that
     re-triggers this observer, which kept the page in an endless rewrite loop. */
  const spans=b.querySelectorAll('span');if(spans.length){spans.forEach(x=>{const want=(!x.classList.contains('aa-icon-action-label-short')||spans.length===1)?'Crown '+count:String(count);if(x.textContent!==want)x.textContent=want})}
 });
}
let crownSyncQueued=false;new MutationObserver(()=>{if(crownSyncQueued)return;crownSyncQueued=true;requestAnimationFrame(()=>{crownSyncQueued=false;syncHomeCrownCounts(document)})}).observe(document.documentElement,{childList:true,subtree:true});
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>syncHomeCrownCounts(document),{once:true});else syncHomeCrownCounts(document);
window.BingoPaidCrowns={open,tiers};
paint();
})();
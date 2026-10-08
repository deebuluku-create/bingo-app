/* Bingo Wall exact mobile preview replacement — 2026-10-08.
   Replaces ONLY the public Bingo Wall renderer. Existing Supabase topic data/actions remain authoritative. */
(function(){'use strict';if(window.__bingoWallExactPreview20261008)return;window.__bingoWallExactPreview20261008=true;
const css=`
#auto-arcade-widget .bwexact{--gold:#f5b800;--ink:#17212b;--muted:#66727e;--line:#e9edf1;--white:#fff;--cyan:#00c7e6;--pink:#ff2d74;color:var(--ink);background:#fff;height:calc(100svh - 1px);display:grid;grid-template-rows:auto 1fr auto;width:100%;max-width:760px;margin:auto;overflow:hidden}
#auto-arcade-widget .bwexact *{box-sizing:border-box}
#auto-arcade-widget .bwexact-head{background:#fff;border-bottom:1px solid var(--line);z-index:20}
#auto-arcade-widget .bwexact-top{height:70px;display:flex;align-items:center;padding:8px 12px;gap:10px}
#auto-arcade-widget .bwexact-brand{font-weight:1000;font-size:26px;letter-spacing:-1px;color:#111;line-height:1}
#auto-arcade-widget .bwexact-brand b{color:var(--gold)}
#auto-arcade-widget .bwexact-tag{font-size:10px;font-weight:800;color:#8a6200;margin-top:3px}
#auto-arcade-widget .bwexact-spacer{flex:1}
#auto-arcade-widget .bwexact-icon{width:40px!important;height:40px!important;min-width:40px!important;min-height:40px!important;border:1px solid #dfe5ea!important;border-radius:50%!important;background:#fff!important;box-shadow:none!important;color:#17212b!important;padding:0!important;font-size:19px!important}
#auto-arcade-widget .bwexact-tabs{display:grid;grid-template-columns:repeat(4,1fr);gap:7px;padding:0 10px 10px}
#auto-arcade-widget .bwexact-tab{border:1px solid #dfe5ea!important;background:#fff!important;box-shadow:none!important;border-radius:999px!important;padding:9px 5px!important;min-height:0!important;font-weight:800!important;color:#3a4651!important}
#auto-arcade-widget .bwexact-tab.active{background:#111827!important;color:#fff!important;border-color:var(--gold)!important;box-shadow:0 0 0 1px var(--gold) inset!important}
#auto-arcade-widget .bwexact-feed{overflow-y:auto;scroll-snap-type:y mandatory;overscroll-behavior-y:contain;background:#fff}
#auto-arcade-widget .bwexact-post{height:100%;min-height:100%;scroll-snap-align:start;position:relative;background:#fff;display:flex;flex-direction:column}
#auto-arcade-widget .bwexact-media{position:relative;flex:1;min-height:0;background:#fff;overflow:hidden}
#auto-arcade-widget .bwexact-media>img,#auto-arcade-widget .bwexact-media>video{display:block;width:100%;height:100%;object-fit:contain;background:#fff}
#auto-arcade-widget .bwexact-empty{width:100%;height:100%;background:linear-gradient(155deg,#7cc7ff 0%,#e9f7ff 45%,#9fd38a 100%)}
#auto-arcade-widget .bwexact-shade{position:absolute;inset:0;background:linear-gradient(180deg,transparent 55%,rgba(0,0,0,.42));pointer-events:none}
#auto-arcade-widget .bwexact-label{position:absolute;left:12px;top:12px;padding:7px 10px;border-radius:999px;background:rgba(15,23,42,.78);color:#fff;font-size:12px;font-weight:800}
#auto-arcade-widget .bwexact-sound{position:absolute;left:12px;top:54px;color:#fff;font-size:13px;font-weight:750;text-shadow:0 1px 4px #000}
#auto-arcade-widget .bwexact-use{display:block;margin-top:6px;font-weight:600}
#auto-arcade-widget .bwexact-side{position:absolute;right:12px;bottom:94px;display:grid;gap:10px;justify-items:center}
#auto-arcade-widget .bwexact-side button{width:48px!important;height:48px!important;min-width:48px!important;min-height:48px!important;border-radius:50%!important;border:1.5px solid #fff!important;background:rgba(17,24,39,.78)!important;box-shadow:0 2px 8px #0004!important;color:#fff!important;padding:0!important;font-size:21px!important}
#auto-arcade-widget .bwexact-side button.boost{border-color:var(--gold)!important;color:var(--gold)!important}
#auto-arcade-widget .bwexact-count{color:#fff;font-size:11px;background:#111b;padding:2px 7px;border-radius:999px;margin-top:-7px}
#auto-arcade-widget .bwexact-caption{position:absolute;left:12px;right:78px;bottom:14px;color:#fff;text-shadow:0 1px 5px #000}
#auto-arcade-widget .bwexact-who{display:flex;align-items:center;gap:9px;margin-bottom:8px}
#auto-arcade-widget .bwexact-avatar{width:42px;height:42px;border-radius:50%;border:2px solid #fff;object-fit:cover;background:#17212b}
#auto-arcade-widget .bwexact-name{font-weight:900}.bwexact-meta{font-size:12px;opacity:.9}.bwexact-copy{font-size:16px;line-height:1.3}
#auto-arcade-widget .bwexact-actions{height:58px;background:#fff;border-top:1px solid var(--line);display:grid;grid-template-columns:repeat(4,1fr);align-items:center;padding:5px 8px;gap:6px}
#auto-arcade-widget .bwexact-actions button{height:40px!important;min-height:40px!important;border-radius:999px!important;background:#fff!important;box-shadow:none!important;font-weight:850!important;border:1px solid #dce3e8!important;color:#24303b!important;padding:0 6px!important}
#auto-arcade-widget .bwexact-actions button:nth-child(1){border-color:var(--gold)!important}#auto-arcade-widget .bwexact-actions button:nth-child(3){border-color:var(--cyan)!important}#auto-arcade-widget .bwexact-actions button:nth-child(4){border-color:var(--pink)!important}
#auto-arcade-widget .bwexact-nav{height:66px;border-top:1px solid var(--line);display:grid;grid-template-columns:repeat(5,1fr);background:#fff;padding-bottom:max(4px,env(safe-area-inset-bottom))}
#auto-arcade-widget .bwexact-nav button{border:0!important;background:#fff!important;box-shadow:none!important;color:#46515c!important;font-size:11px!important;font-weight:750!important;padding:2px!important;min-height:0!important;border-radius:0!important}
#auto-arcade-widget .bwexact-nav button span{display:block;font-size:21px;margin-bottom:2px}.bwexact-nav button.active{color:#111!important}.bwexact-nav button.active span{color:var(--gold)}
#auto-arcade-widget .bwexact-nav .post span{background:#111;color:#fff;border:2px solid var(--gold);border-radius:12px;width:42px;margin:0 auto 2px}
#auto-arcade-widget .bwexact-sheet{position:fixed;left:50%;bottom:0;transform:translate(-50%,110%);width:min(760px,100%);background:#fff;border-radius:22px 22px 0 0;box-shadow:0 -12px 40px #0003;padding:18px;transition:.25s;z-index:10080;color:#17212b}
#auto-arcade-widget .bwexact-sheet.open{transform:translate(-50%,0)}#auto-arcade-widget .bwexact-sheet-close{float:right;border:0!important;background:#eef2f5!important;border-radius:50%!important;width:34px!important;height:34px!important;padding:0!important;color:#17212b!important}
#auto-arcade-widget .bwexact-comment{display:flex;gap:9px;padding:9px 0;border-top:1px solid var(--line)}#auto-arcade-widget .bwexact-comment .bwexact-avatar{width:34px;height:34px;border-color:var(--gold)}
#auto-arcade-widget .bwexact-commentbox{display:grid;grid-template-columns:1fr auto;gap:8px;margin-top:10px}#auto-arcade-widget .bwexact-commentbox input{border:1px solid #dce3e8;border-radius:999px;padding:10px 14px;background:#fff;color:#17212b}#auto-arcade-widget .bwexact-commentbox button{border:1px solid var(--gold)!important;border-radius:999px!important;background:#111827!important;color:#fff!important;padding:8px 14px!important}
@media(min-width:761px){#auto-arcade-widget .bwexact{height:min(920px,100svh)}}
`;
function addStyle(){if(document.getElementById('bingo-wall-exact-preview-css'))return;const s=document.createElement('style');s.id='bingo-wall-exact-preview-css';s.textContent=css;document.head.appendChild(s)}
function idq(v){return JSON.stringify(String(v))}
function wallPost(t){
 const author=aaTopicAuthorMeta(t),name=aaMemberDisplayName(author),comments=aaTopicCommentsFor(t),loves=aaTopicLoveCount(t),saved=aaTopicIsSaved(t.id);
 const media=Array.isArray(t.media)?t.media:[],idx=aaTopicMediaIndex(t.id,media.length),item=media[idx],src=aaTopicMediaSrc(item),video=!!(src&&item&&item.type==='video');
 const mediaHtml=src?(video?`<video src="${bingoSafeMediaAttr(src)}" muted playsinline preload="auto" autoplay></video>`:`<img src="${bingoSafeMediaAttr(src)}" alt="" loading="eager">`):'<div class="bwexact-empty"></div>';
 const copy=[t.title,t.body].filter(Boolean).map(esc).join('<br>');
 return `<article class="bwexact-post" data-topic-id="${esc(t.id)}"><div class="bwexact-media">${mediaHtml}<div class="bwexact-shade"></div><div class="bwexact-label">👑 ${loves} · 👁 ${Number(aaTopicCountsFor(t.id)?.views||0)}</div><div class="bwexact-sound">♫ Original sound – ${esc(name)}<span class="bwexact-use">Use this sound ›</span></div><div class="bwexact-side"><button type="button" onclick="aaTopicLove(${idq(t.id)})">♛</button><div class="bwexact-count">${loves}</div><button type="button" onclick="bingoWallExactComments(${idq(t.id)})">💬</button><div class="bwexact-count">${comments.length}</div><button type="button" onclick="aaTopicShare(${idq(t.id)})">↗</button><div class="bwexact-count">Share</div><button type="button" class="boost" onclick="if(typeof openContentBoost==='function')openContentBoost(aaTopics().find(x=>String(x.id)===${idq(t.id)}),'topic');else toast('Boost')">⚡</button><div class="bwexact-count">Boost</div><button type="button" onclick="aaTopicToggleSave(${idq(t.id)})">•••</button></div><div class="bwexact-caption"><div class="bwexact-who"><img class="bwexact-avatar" src="${bingoSafeMediaAttr(aaProfilePhoto(author.photo))}" onerror="aaProfileImgFallback(this)" onclick="openSeller(${idq(t.authorId||'')})"><div><div class="bwexact-name">${esc(name)}${author.verified?' ✓':''}</div><div class="bwexact-meta">${t.createdAt?esc(new Date(t.createdAt).toLocaleDateString('en-KE')):''} · ${esc(author.location||'Kenya')} · 🌐</div></div></div><div class="bwexact-copy">${copy||'Bingo post'}</div></div></div><div class="bwexact-actions"><button type="button" onclick="aaTopicLove(${idq(t.id)})">👑 Crowns</button><button type="button" onclick="bingoWallExactComments(${idq(t.id)})">Comments</button><button type="button" onclick="aaTopicShare(${idq(t.id)})">Share</button><button type="button" onclick="if(typeof openContentBoost==='function')openContentBoost(aaTopics().find(x=>String(x.id)===${idq(t.id)}),'topic');else toast('Boost')">Boost</button></div></article>`;
}
window.bingoWallExactComments=function(id){window.__bwExactTopic=id;const sh=document.getElementById('bwexact-sheet');if(!sh)return;const t=aaTopics().find(x=>String(x.id)===String(id));const list=t?aaTopicCommentsFor(t):[];const body=document.getElementById('bwexact-comments');body.innerHTML=list.length?list.slice(-8).map(c=>`<div class="bwexact-comment"><img class="bwexact-avatar" src="${bingoSafeMediaAttr(aaProfilePhoto(c.authorPhoto))}" onerror="aaProfileImgFallback(this)"><div><b>${esc(c.authorName||'Bingo Member')}</b><br><span>${esc(c.text||'')}</span></div></div>`).join(''):'<div class="bwexact-comment">No comments yet.</div>';const input=document.getElementById('bwexact-input');if(input)input.value=aaCommentDraftText[id]||'';sh.classList.add('open')};
window.bingoWallExactSendComment=function(){const id=window.__bwExactTopic,input=document.getElementById('bwexact-input');if(!id||!input)return;aaCommentDraftText[id]=input.value;aaTopicComment(id);document.getElementById('bwexact-sheet')?.classList.remove('open')};
function renderer(){
 const all=aaTopics().filter(t=>!t.hiddenFromPublic).sort((a,b)=>new Date(b.createdAt||0)-new Date(a.createdAt||0));aaLoadTopicCounts(all.map(t=>t.id));
 const posts=all.length?all.map(wallPost).join(''):'<div style="padding:40px;text-align:center">No posts yet.</div>';
 return `<section class="bwexact"><header class="bwexact-head"><div class="bwexact-top"><div><div class="bwexact-brand"><b>B</b>ingo 😊</div><div class="bwexact-tag">Kenyans, we did it.</div></div><div class="bwexact-spacer"></div><button class="bwexact-icon" type="button" onclick="aaOpenSearch('all')">⌕</button><button class="bwexact-icon" type="button" onclick="document.querySelectorAll('.bwexact video').forEach(v=>v.muted=!v.muted)">🔊</button></div><div class="bwexact-tabs"><button class="bwexact-tab active" type="button">All Kenya</button><button class="bwexact-tab" type="button">Following</button><button class="bwexact-tab" type="button">Videos</button><button class="bwexact-tab" type="button">Photos</button></div></header><main class="bwexact-feed" id="bwexact-feed">${posts}</main><nav class="bwexact-nav"><button type="button" class="active" onclick="goHome()"><span>⌂</span>Home</button><button type="button" onclick="aaOpenBingoTopicsFeed()"><span>#</span>Topics</button><button type="button" class="post" onclick="state.wallComposerOpen=true;render()"><span>＋</span>Post</button><button type="button" onclick="openInbox()"><span>💬</span>Messages</button><button type="button" onclick="goAccount()"><span>◉</span>Profile</button></nav><div class="bwexact-sheet" id="bwexact-sheet"><button class="bwexact-sheet-close" type="button" onclick="this.parentElement.classList.remove('open')">×</button><h3>Comments</h3><div id="bwexact-comments"></div><div class="bwexact-commentbox"><input id="bwexact-input" placeholder="Write a comment…" oninput="if(window.__bwExactTopic)aaCommentDraftText[window.__bwExactTopic]=this.value"><button type="button" onclick="bingoWallExactSendComment()">Post</button></div></div></section>`;
}
function install(){
 addStyle();
 if(typeof window.aaPublicTopicsFeedHTML!=='function')return false;
 window.aaPublicTopicsFeedHTML=renderer;
 if(window.state&&state.view==='topics'&&typeof window.render==='function')render();
 return true;
}
let tries=0,t=setInterval(()=>{if(install()||++tries>80)clearInterval(t)},100);
addStyle();
document.addEventListener('play',e=>{if(e.target?.matches?.('.bwexact video'))document.querySelectorAll('.bwexact video').forEach(v=>{if(v!==e.target)try{v.pause()}catch(_){}})},true);
})();
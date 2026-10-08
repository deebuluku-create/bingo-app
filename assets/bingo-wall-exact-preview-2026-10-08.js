/* Bingo Wall — surgical visual/behavior repair, 2026-10-08.
   Scope: public Bingo Wall renderer only. Does not replace the mother HTML,
   Supabase data model, authentication, existing topic persistence, or other pages. */
(function(){
  'use strict';
  if(window.__bingoWallSurgical20261008)return;
  window.__bingoWallSurgical20261008=true;
  const CSS=`
  #auto-arcade-widget .bw-surgical{--gold:#f2b800;--ink:#17212b;--muted:#66727e;--line:#e8edf1;--blue:#168df5;width:100%;max-width:980px;margin:0 auto;background:#fff;color:var(--ink);min-height:100vh;overflow:visible;position:relative}
  #auto-arcade-widget .bw-surgical *{box-sizing:border-box}
  #auto-arcade-widget .bw-head{position:sticky;top:0;z-index:50;background:#fff;border-bottom:1px solid var(--line)}
  #auto-arcade-widget .bw-top{min-height:92px;display:flex;align-items:center;padding:8px 18px;gap:14px;background:#fff}
  #auto-arcade-widget .bw-brand{display:flex;align-items:center;gap:14px;min-width:0}
  #auto-arcade-widget .bw-logo{width:154px;height:auto;max-height:78px;object-fit:contain;object-position:left center;display:block;background:transparent!important;border:0!important;box-shadow:none!important}
  #auto-arcade-widget .bw-wall-word{font-size:31px;font-weight:900;letter-spacing:.01em;white-space:nowrap;color:#111}
  #auto-arcade-widget .bw-head-actions{margin-left:auto;display:flex;align-items:center;gap:8px}
  #auto-arcade-widget .bw-head-btn{width:48px!important;height:48px!important;min-width:48px!important;min-height:48px!important;border:0!important;border-radius:50%!important;background:#fff!important;box-shadow:none!important;color:#17212b!important;padding:0!important;display:grid!important;place-items:center!important;position:relative!important;font-size:0!important}
  #auto-arcade-widget .bw-head-btn svg{width:28px;height:28px;display:block}
  #auto-arcade-widget .bw-notice-dot{position:absolute;right:7px;top:7px;width:9px;height:9px;border-radius:50%;background:#f33}
  #auto-arcade-widget .bw-tabs{display:grid;grid-template-columns:repeat(5,1fr);background:#fff;border-top:1px solid #f1f3f5}
  #auto-arcade-widget .bw-tab{min-height:78px;border:0!important;border-radius:0!important;background:#fff!important;box-shadow:none!important;color:#52606d!important;padding:8px 4px!important;display:flex!important;flex-direction:column!important;align-items:center!important;justify-content:center!important;gap:4px!important;font-size:15px!important;font-weight:650!important;position:relative!important}
  #auto-arcade-widget .bw-tab svg{width:29px;height:29px;stroke:currentColor;fill:none}
  #auto-arcade-widget .bw-tab.active{color:var(--blue)!important}
  #auto-arcade-widget .bw-tab.active:after{content:"";position:absolute;left:0;right:0;bottom:0;height:3px;background:var(--blue)}
  #auto-arcade-widget .bw-feed{position:relative;background:#fff;padding-bottom:80px;overflow:visible}
  #auto-arcade-widget .bw-feed:before{content:"";position:absolute;left:42px;top:0;bottom:0;width:3px;background:var(--gold);z-index:0}
  #auto-arcade-widget .bw-post{position:relative;z-index:1;background:#fff;margin:0;padding:22px 22px 22px 82px;border:0!important;border-radius:0!important;box-shadow:none!important}
  #auto-arcade-widget .bw-marker{position:absolute;left:31px;top:44px;width:24px;height:24px;border:4px solid var(--gold);border-radius:50%;background:#fff;z-index:3}
  #auto-arcade-widget .bw-post-head{display:flex;align-items:flex-start;gap:10px;min-width:0}
  #auto-arcade-widget .bw-avatar{width:54px;height:54px;border-radius:50%;object-fit:cover;background:#fff;border:1px solid #e7ebef;flex:0 0 auto}
  #auto-arcade-widget .bw-author-wrap{min-width:0;flex:1;padding-top:1px}
  #auto-arcade-widget .bw-author-line{display:flex;align-items:center;gap:6px;min-width:0;flex-wrap:wrap}
  #auto-arcade-widget .bw-author{font-size:18px;font-weight:850;line-height:1.2;color:#111}
  #auto-arcade-widget .bw-verified{width:18px;height:18px;border-radius:50%;background:#168df5;color:#fff;display:inline-grid;place-items:center;font-size:12px;font-weight:900}
  #auto-arcade-widget .bw-meta{font-size:14px;color:var(--muted);line-height:1.3}
  #auto-arcade-widget .bw-options{position:relative;margin-left:auto;flex:0 0 auto}
  #auto-arcade-widget .bw-options>summary{list-style:none;cursor:pointer;color:#65717d;font-size:25px;line-height:1;padding:0 4px}
  #auto-arcade-widget .bw-options>summary::-webkit-details-marker{display:none}
  #auto-arcade-widget .bw-options>div{position:absolute;right:0;top:30px;z-index:30;background:#fff;border:1px solid #dfe5ea;border-radius:12px;padding:6px;width:190px;box-shadow:0 12px 28px #0002}
  #auto-arcade-widget .bw-options button{display:block;width:100%;border:0;background:#fff;color:#17212b;text-align:left;padding:10px;border-radius:8px;cursor:pointer}
  #auto-arcade-widget .bw-options button:hover{background:#f5f7f9}
  #auto-arcade-widget .bw-content{margin-top:6px}
  #auto-arcade-widget .bw-title{font-size:22px;line-height:1.28;font-weight:800;margin:0 0 3px;color:#111;word-break:break-word}
  #auto-arcade-widget .bw-body{font-size:17px;line-height:1.45;margin:0 0 12px;color:#17212b;white-space:pre-wrap;word-break:break-word}
  #auto-arcade-widget .bw-media{width:100%;max-width:760px;margin:0 0 10px;border-radius:12px;overflow:hidden;background:#fff;position:relative}
  #auto-arcade-widget .bw-media img,#auto-arcade-widget .bw-media video{display:block;width:100%;height:auto;max-width:100%;max-height:78vh;object-fit:contain;background:#fff}
  #auto-arcade-widget .bw-media video{cursor:default}
  #auto-arcade-widget .bw-media-nav{position:absolute;top:50%;transform:translateY(-50%);width:34px!important;height:34px!important;border-radius:50%!important;border:0!important;background:#0008!important;color:#fff!important;box-shadow:none!important;padding:0!important;z-index:4}
  #auto-arcade-widget .bw-media-nav.prev{left:10px}#auto-arcade-widget .bw-media-nav.next{right:10px}
  #auto-arcade-widget .bw-media-count{position:absolute;right:10px;top:10px;background:#0009;color:#fff;border-radius:99px;padding:4px 8px;font-size:11px;font-weight:800}
  #auto-arcade-widget .bw-actions{display:grid;grid-template-columns:repeat(3,1fr);max-width:720px;border-top:1px solid var(--line);padding-top:5px}
  #auto-arcade-widget .bw-action{border:0!important;background:#fff!important;box-shadow:none!important;color:#46515c!important;padding:9px 4px!important;min-height:42px!important;font-size:14px!important;font-weight:650!important;display:flex!important;align-items:center!important;justify-content:center!important;gap:7px!important}
  #auto-arcade-widget .bw-action svg{width:21px;height:21px;stroke:currentColor;fill:none}
  #auto-arcade-widget .bw-action.crown{color:#8a6500!important}
  #auto-arcade-widget .bw-comments{max-width:720px;margin-top:4px}
  #auto-arcade-widget .bw-comment-row{display:flex;gap:9px;padding:9px 0}
  #auto-arcade-widget .bw-comment-avatar{width:36px;height:36px;border-radius:50%;object-fit:cover;flex:0 0 auto;border:1px solid #e5e9ed}
  #auto-arcade-widget .bw-comment-copy{min-width:0;flex:1}
  #auto-arcade-widget .bw-comment-name{font-size:13px;font-weight:800;color:#111}
  #auto-arcade-widget .bw-comment-text{font-size:14px;line-height:1.4;color:#27323c;word-break:break-word}
  #auto-arcade-widget .bw-comment-meta{font-size:11px;color:#7a8691;margin-top:2px}
  #auto-arcade-widget .bw-more-comments{border:0!important;background:transparent!important;box-shadow:none!important;color:#52606d!important;padding:5px 0!important;font-size:13px!important;font-weight:700!important;text-align:left!important}
  #auto-arcade-widget .bw-comment-box{display:flex;gap:8px;align-items:center;margin-top:6px;max-width:720px}
  #auto-arcade-widget .bw-comment-box input{flex:1;min-width:0;border:1px solid #d8dfe5;border-radius:999px;background:#fff;color:#17212b;padding:10px 14px;outline:0}
  #auto-arcade-widget .bw-comment-send{width:40px!important;height:40px!important;min-width:40px!important;border-radius:50%!important;border:1px solid var(--gold)!important;background:#fff!important;color:#8a6500!important;box-shadow:none!important;padding:0!important}
  #auto-arcade-widget .bw-empty{padding:70px 20px;text-align:center;color:#66727e}
  @media(max-width:700px){
    #auto-arcade-widget .bw-top{min-height:78px;padding:6px 10px;gap:9px}
    #auto-arcade-widget .bw-logo{width:128px;max-height:62px}
    #auto-arcade-widget .bw-wall-word{font-size:24px}
    #auto-arcade-widget .bw-head-actions{gap:0}
    #auto-arcade-widget .bw-head-btn{width:40px!important;height:40px!important;min-width:40px!important;min-height:40px!important}
    #auto-arcade-widget .bw-head-btn svg{width:24px;height:24px}
    #auto-arcade-widget .bw-tab{min-height:68px;font-size:12px!important}
    #auto-arcade-widget .bw-tab svg{width:24px;height:24px}
    #auto-arcade-widget .bw-feed:before{left:27px;width:3px}
    #auto-arcade-widget .bw-post{padding:17px 10px 18px 61px}
    #auto-arcade-widget .bw-marker{left:17px;top:34px;width:21px;height:21px;border-width:3px}
    #auto-arcade-widget .bw-avatar{width:47px;height:47px}
    #auto-arcade-widget .bw-author{font-size:15px}
    #auto-arcade-widget .bw-meta{font-size:12px}
    #auto-arcade-widget .bw-title{font-size:19px}
    #auto-arcade-widget .bw-body{font-size:15px}
    #auto-arcade-widget .bw-action{font-size:12px!important}
  }

  /* Approved Golden Timeline Wall visual alignment; confined to Wall renderer. */
  #auto-arcade-widget .bw-surgical{max-width:none!important;width:100%!important;background:#fff!important}
  #auto-arcade-widget .bw-top{min-height:86px;padding:10px 22px;gap:18px}
  #auto-arcade-widget .bw-logo{width:150px;max-height:72px}
  #auto-arcade-widget .bw-wall-word{font-size:30px;font-weight:800}
  #auto-arcade-widget .bw-tabs{border-top:1px solid #f2f4f6}
  #auto-arcade-widget .bw-tab{min-height:76px;font-weight:600!important}
  #auto-arcade-widget .bw-feed:before{left:47px;background:linear-gradient(#f2b400,#ffd34d,#f2b400)}
  #auto-arcade-widget .bw-post{padding:22px 28px 22px 94px!important;max-width:none!important}
  #auto-arcade-widget .bw-marker{left:36px;top:42px;width:22px;height:22px;border:4px solid #f2b400}
  #auto-arcade-widget .bw-post-head{position:relative;min-height:54px}
  #auto-arcade-widget .bw-content,#auto-arcade-widget .bw-media,#auto-arcade-widget .bw-actions,#auto-arcade-widget .bw-comments,#auto-arcade-widget .bw-comment-box{margin-left:64px;max-width:720px}
  #auto-arcade-widget .bw-body{font-size:17px;line-height:1.42}
  #auto-arcade-widget .bw-media{width:min(100%,520px);max-width:520px;background:#fff}
  #auto-arcade-widget .bw-media img,#auto-arcade-widget .bw-media video{width:100%;height:auto;max-height:none;object-fit:contain}
  #auto-arcade-widget .bw-actions{border-top:0;padding-top:0;grid-template-columns:repeat(3,1fr)}
  #auto-arcade-widget .bw-action{justify-content:flex-start!important;background:transparent!important;color:#596979!important;font-weight:500!important}
  @media(max-width:700px){
    #auto-arcade-widget .bw-top{min-height:72px;padding:8px 12px;gap:9px}
    #auto-arcade-widget .bw-logo{width:118px;max-height:58px}
    #auto-arcade-widget .bw-wall-word{font-size:22px}
    #auto-arcade-widget .bw-tab{min-height:65px;font-size:12px!important}
    #auto-arcade-widget .bw-feed:before{left:27px}
    #auto-arcade-widget .bw-post{padding:17px 12px 17px 70px!important}
    #auto-arcade-widget .bw-marker{left:17px;top:35px;width:20px;height:20px;border-width:4px}
    #auto-arcade-widget .bw-post-head{min-height:48px}
    #auto-arcade-widget .bw-content,#auto-arcade-widget .bw-media,#auto-arcade-widget .bw-actions,#auto-arcade-widget .bw-comments,#auto-arcade-widget .bw-comment-box{margin-left:0}
    #auto-arcade-widget .bw-media{max-width:520px}
  }
  `;
  function installCSS(){if(document.getElementById('bingo-wall-surgical-css'))return;const s=document.createElement('style');s.id='bingo-wall-surgical-css';s.textContent=CSS;document.head.appendChild(s)}
  const j=v=>JSON.stringify(String(v??''));
  function icon(n){const m={search:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="10.8" cy="10.8" r="6.8"/><path d="m16 16 5 5"/></svg>',bell:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M18 9a6 6 0 0 0-12 0c0 7-3 7-3 8h18c0-1-3-1-3-8"/><path d="M10 21h4"/></svg>',mail:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><rect x="3" y="5" width="18" height="14" rx="2"/><path d="m4 7 8 6 8-6"/></svg>',home:'<svg viewBox="0 0 24 24" fill="currentColor"><path d="m3 11 9-7 9 7v9a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/></svg>',crown:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="m4 7 4 4 4-7 4 7 4-4-2 11H6z"/><path d="M6 21h12"/></svg>',market:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M4 9h16v11H4z"/><path d="M3 9 5 4h14l2 5M8 9v3M12 9v3M16 9v3"/></svg>',comments:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M5 5h14a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-8l-5 3v-3H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z"/><path d="M8 10h.01M12 10h.01M16 10h.01"/></svg>',profile:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><circle cx="12" cy="8" r="3.5"/><path d="M5 21c.8-4 3-6 7-6s6.2 2 7 6"/></svg>',comment:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M5 5h14a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2h-7l-5 3v-3H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2z"/></svg>',share:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8"><path d="M4 12v7a1 1 0 0 0 1 1h14a1 1 0 0 0 1-1v-7"/><path d="M12 16V3m0 0L7 8m5-5 5 5"/></svg>'};return m[n]||''}
  function topicList(){let list=(typeof aaTopics==='function'?aaTopics():[]).filter(t=>!t.hiddenFromPublic);const f=window.__bwSurgicalFilter||'all';if(f==='crown')list.sort((a,b)=>aaTopicLoveCount(b)-aaTopicLoveCount(a));else if(f==='comments')list.sort((a,b)=>aaTopicCommentsFor(b).length-aaTopicCommentsFor(a).length);else list.sort((a,b)=>new Date(b.createdAt||0)-new Date(a.createdAt||0));return list}
  function routeFilter(f){window.__bwSurgicalFilter=f;if(window.state)state.view='topics';if(typeof window.render==='function')render()}
  function header(){return `<header class="bw-head"><div class="bw-top"><div class="bw-brand">${bingoAppLogoHTML({className:'bw-logo',alt:'Bingo — All Kenyans, One Market.'})}<span class="bw-wall-word">WALL</span></div><div class="bw-head-actions"><button class="bw-head-btn" type="button" aria-label="Search" onclick="aaOpenSearch('all')">${icon('search')}</button><button class="bw-head-btn" type="button" aria-label="Notifications" onclick="goAccount();if(typeof aaOpenAccountNotifications==='function')aaOpenAccountNotifications()">${icon('bell')}<span class="bw-notice-dot"></span></button><button class="bw-head-btn" type="button" aria-label="Messages" onclick="openInbox()">${icon('mail')}</button></div></div><nav class="bw-tabs" aria-label="Bingo Wall navigation"><button class="bw-tab ${window.__bwSurgicalFilter==='all'?'active':''}" onclick="window.__bingoWallSurgicalWallTab('all')">${icon('home')}<span>Home</span></button><button class="bw-tab ${window.__bwSurgicalFilter==='crown'?'active':''}" onclick="window.__bingoWallSurgicalWallTab('crown')">${icon('crown')}<span>Crown</span></button><button class="bw-tab" onclick="aaOpenMarket()">${icon('market')}<span>Marketplace</span></button><button class="bw-tab ${window.__bwSurgicalFilter==='comments'?'active':''}" onclick="window.__bingoWallSurgicalWallTab('comments')">${icon('comments')}<span>Comments</span></button><button class="bw-tab" onclick="goAccount()">${icon('profile')}<span>Profile</span></button></nav></header>`}
  function commentsHTML(t){const comments=(typeof aaTopicCommentsFor==='function'?aaTopicCommentsFor(t):[]).slice().sort((a,b)=>Number(b.likes||0)-Number(a.likes||0)||new Date(b.createdAt||0)-new Date(a.createdAt||0));if(!comments.length)return '';const c=comments[0];const photo=typeof aaProfilePhoto==='function'?aaProfilePhoto(c.authorPhoto):'';const more=comments.length>1?`<button class="bw-more-comments" type="button" onclick="aaTopicSetCommentView(${j(t.id)},'all')">View more comments (${comments.length-1})</button>`:'';return `<div class="bw-comments"><div class="bw-comment-row"><img class="bw-comment-avatar" src="${typeof bingoSafeMediaAttr==='function'?bingoSafeMediaAttr(photo):esc(photo)}" alt="" onerror="aaProfileImgFallback(this)"><div class="bw-comment-copy"><div class="bw-comment-name">${esc(c.authorName||'Bingo Member')}</div><div class="bw-comment-text">${esc(c.text||'')}</div><div class="bw-comment-meta">${c.createdAt?esc(new Date(c.createdAt).toLocaleString('en-KE',{hour:'2-digit',minute:'2-digit'})):''}</div></div></div>${more}</div>`}
  function mediaHTML(t){const media=Array.isArray(t.media)?t.media:[];if(!media.length)return '';const idx=typeof aaTopicMediaIndex==='function'?aaTopicMediaIndex(t.id,media.length):0;const item=media[idx];const src=typeof aaTopicMediaSrc==='function'?aaTopicMediaSrc(item):'';if(!src)return '';const isVideo=item?.type==='video';const m=isVideo?`<video src="${bingoSafeMediaAttr(src)}" muted playsinline preload="metadata" autoplay loop></video>`:`<img src="${bingoSafeMediaAttr(src)}" alt="" loading="lazy">`;const nav=media.length>1?`<span class="bw-media-count">${idx+1}/${media.length}</span><button class="bw-media-nav prev" type="button" aria-label="Previous" onclick="event.stopPropagation();aaTopicMediaNav(${j(t.id)},-1,${media.length})">‹</button><button class="bw-media-nav next" type="button" aria-label="Next" onclick="event.stopPropagation();aaTopicMediaNav(${j(t.id)},1,${media.length})">›</button>`:'';return `<div class="bw-media">${m}${nav}</div>`}
  function postHTML(t){const author=aaTopicAuthorMeta(t),saved=aaTopicIsSaved(t.id),loved=aaTopicHasMyLove(t),comments=aaTopicCommentsFor(t),owner=String(t.authorId||'')===String(state.user?.id||'');const options=`<details class="bw-options"><summary aria-label="Post options">•••</summary><div>${owner&&state.isLoggedIn?`<button type="button" onclick="aaOpenEditTopic(${j(t.id)})">Edit post</button><button type="button" onclick="aaDeleteBingoTopic(${j(t.id)})">Delete post</button>`:''}<button type="button" onclick="aaTopicToggleSave(${j(t.id)})">${saved?'Saved':'Save / Download'}</button><button type="button" onclick="aaTopicReport(${j(t.id)})">Report post</button></div></details>`;const content=`${t.title?`<h2 class="bw-title" style="${t.titleFmt?aaTextFormatCSS(t.titleFmt):''}">${esc(t.title)}</h2>`:''}${t.body?`<p class="bw-body" style="${t.bodyFmt?aaTextFormatCSS(t.bodyFmt):''}">${esc(t.body)}</p>`:''}`;const commentDraft=(window.aaCommentDraftText&&aaCommentDraftText[t.id])||'';return `<article class="bw-post" data-bw-topic-id="${esc(t.id)}"><span class="bw-marker" aria-hidden="true"></span><header class="bw-post-head"><img class="bw-avatar" src="${bingoSafeMediaAttr(aaProfilePhoto(author.photo))}" alt="" onerror="aaProfileImgFallback(this)" onclick="openSeller(${j(t.authorId||'')})"><div class="bw-author-wrap"><div class="bw-author-line"><b class="bw-author" onclick="openSeller(${j(t.authorId||'')})">${aaBingo50NameHTML(author.name,false)}</b>${author.verified?'<span class="bw-verified">✓</span>':''}<span class="bw-meta">· ${t.createdAt?esc(new Date(t.createdAt).toLocaleString('en-KE',{day:'numeric',month:'short',hour:'2-digit',minute:'2-digit'})):''}</span></div><div class="bw-meta">${esc(author.location||'Kenya')} · 🌐 Public</div></div>${options}</header><div class="bw-content">${content}</div>${mediaHTML(t)}<div class="bw-actions"><button class="bw-action crown" type="button" aria-pressed="${loved}" onclick="aaTopicLove(${j(t.id)})">${icon('crown')}<span>${aaTopicLoveCount(t)}</span></button><button class="bw-action comment" type="button" onclick="aaTopicSetCommentView(${j(t.id)},'more')">${icon('comment')}<span>${comments.length}</span></button><button class="bw-action share" type="button" onclick="aaTopicShare(${j(t.id)})">${icon('share')}<span>Share</span></button></div>${commentsHTML(t)}<div class="bw-comment-box"><input id="bw-comment-${esc(t.id)}" value="${esc(commentDraft)}" placeholder="Write a comment…" aria-label="Write a comment" oninput="aaCommentDraftText[${j(t.id)}]=this.value" onkeydown="if(event.key==='Enter'){event.preventDefault();aaTopicComment(${j(t.id)})}"><button class="bw-comment-send" type="button" aria-label="Send comment" onclick="aaTopicComment(${j(t.id)})">➤</button></div></article>`}
  function wireVideos(){const videos=[...document.querySelectorAll('#auto-arcade-widget .bw-surgical .bw-media video')];if(!videos.length)return;if(window.__bwVideoObserver)try{window.__bwVideoObserver.disconnect()}catch(e){}window.__bwVideoObserver=new IntersectionObserver(entries=>entries.forEach(e=>{const v=e.target;if(e.isIntersecting&&e.intersectionRatio>=.55){v.muted=true;v.playsInline=true;v.play().catch(()=>{})}else v.pause()}),{threshold:[0,.55,1]});videos.forEach(v=>{v.muted=true;v.playsInline=true;window.__bwVideoObserver.observe(v)})}
  function renderer(){const list=topicList();if(typeof aaLoadTopicCounts==='function'&&list.length)aaLoadTopicCounts(list.map(t=>t.id));const posts=list.length?list.map(postHTML).join(''):'<div class="bw-empty">No public posts yet.</div>';setTimeout(wireVideos,0);return `<section class="bw-surgical">${header()}<main class="bw-feed" aria-live="polite">${posts}</main></section>`}
  window.__bingoWallSurgicalRenderer=renderer;window.__bingoWallSurgicalWallTab=function(filter){routeFilter(filter)};
  function install(){installCSS();if(typeof window.aaPublicTopicsFeedHTML!=='function')return false;window.aaPublicTopicsFeedHTML=renderer;return true}
  install();let tries=0;const timer=setInterval(()=>{install();if(++tries>100)clearInterval(timer)},100);
  const guard=setInterval(()=>{if(window.state?.view==='topics'&&window.aaPublicTopicsFeedHTML!==renderer)window.aaPublicTopicsFeedHTML=renderer},250);setTimeout(()=>clearInterval(guard),30000);
  installCSS();
})();
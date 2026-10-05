/* Bingo media stability — Home + Topic only, 2026-10-05.
   Preserve uploaded portrait/landscape orientation. No routing/actions/data changes. */
(function(){'use strict';if(window.__bingoMediaStability)return;window.__bingoMediaStability=1;
const css=document.createElement('style');css.textContent=`
#auto-arcade-widget .aa360-item video,
#auto-arcade-widget [data-bingo-wall-detail="1"] video,
#auto-arcade-widget #bingoWallDetail video,
#auto-arcade-widget .bingo-wall-detail video,
#auto-arcade-widget .bingo-topic-detail video{display:block!important;width:100%!important;height:auto!important;aspect-ratio:auto!important;object-fit:contain!important;background:#000!important}
#auto-arcade-widget .aa360-item img:not(.bingo-feed-clean-avatar),
#auto-arcade-widget [data-bingo-wall-detail="1"] img:not(.bingo-feed-clean-avatar),
#auto-arcade-widget #bingoWallDetail img:not(.bingo-feed-clean-avatar),
#auto-arcade-widget .bingo-wall-detail img:not(.bingo-feed-clean-avatar),
#auto-arcade-widget .bingo-topic-detail img:not(.bingo-feed-clean-avatar){display:block!important;max-width:100%!important;width:auto!important;height:auto!important;aspect-ratio:auto!important;object-fit:contain!important;margin-left:auto!important;margin-right:auto!important}
`;document.head.appendChild(css);
function tune(v){if(!v||v.dataset.bingoStableMedia)return;v.dataset.bingoStableMedia='1';v.preload='metadata';v.playsInline=true;v.setAttribute('playsinline','');}
function scan(n=document){if(n.matches?.('video'))tune(n);n.querySelectorAll?.('video').forEach(tune)}
new MutationObserver(ms=>ms.forEach(m=>m.addedNodes.forEach(n=>{if(n.nodeType===1)scan(n)}))).observe(document.documentElement,{childList:true,subtree:true});
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',()=>scan(),{once:true});else scan();
})();
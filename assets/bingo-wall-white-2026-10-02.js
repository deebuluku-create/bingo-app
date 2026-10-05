/* Bingo Wall white-mode activator — presentation only. */
(function(){
  function syncBingoWallWhite(){
    try{
      var on=!!(window.state&&window.state.view==='topics');
      document.body&&document.body.classList.toggle('bingo-wall-white-mode',on);
      if(on){
        var root=document.querySelector('#auto-arcade-widget main');
        if(root){
          var logos=[].slice.call(root.querySelectorAll('img')).filter(function(i){return /bingo/i.test((i.alt||'')+' '+(i.src||''))});
          var seen={};logos.forEach(function(i){var k=(i.currentSrc||i.src||i.alt||'bingo').replace(/[?#].*$/,'');if(seen[k]){var host=i.closest('.bingo-header-stack,.aa-v69-card,.aa-post-card,header')||i;host.style.setProperty('display','none','important');host.setAttribute('data-bingo-duplicate-identity','1')}else seen[k]=i});
        }
      }
    }catch(e){}
  }
  syncBingoWallWhite();
  new MutationObserver(syncBingoWallWhite).observe(document.documentElement,{childList:true,subtree:true});
  addEventListener('hashchange',syncBingoWallWhite);
  addEventListener('popstate',syncBingoWallWhite);
  addEventListener('click',function(){setTimeout(syncBingoWallWhite,0)},true);
})();

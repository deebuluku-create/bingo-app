/* Bingo Wall white-mode activator — presentation only. */
(function(){
  function syncBingoWallWhite(){
    try{
      var on=!!(window.state&&window.state.view==='topics');
      document.body&&document.body.classList.toggle('bingo-wall-white-mode',on);
    }catch(e){}
  }
  syncBingoWallWhite();
  new MutationObserver(syncBingoWallWhite).observe(document.documentElement,{childList:true,subtree:true});
  addEventListener('hashchange',syncBingoWallWhite);
  addEventListener('popstate',syncBingoWallWhite);
  addEventListener('click',function(){setTimeout(syncBingoWallWhite,0)},true);
})();

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
  /* Wall media authority: preserve the uploaded video's natural portrait/landscape ratio,
     autoplay the visible Wall video inline, and never require the legacy centre Play button. */
  var wallVideos=new Set(),wallIO=null;
  function wireWallVideo(v){
    if(!v||v.dataset.bingoWallMedia)return;v.dataset.bingoWallMedia='1';wallVideos.add(v);
    v.playsInline=true;v.setAttribute('playsinline','');v.autoplay=true;v.controls=false;v.preload='auto';
    v.style.setProperty('width','100%','important');v.style.setProperty('height','auto','important');
    v.style.setProperty('aspect-ratio','auto','important');v.style.setProperty('object-fit','contain','important');
    if(!wallIO)wallIO=new IntersectionObserver(function(es){es.forEach(function(e){
      var x=e.target;if(e.isIntersecting&&e.intersectionRatio>=.35){
        wallVideos.forEach(function(o){if(o!==x&&!o.paused)try{o.pause()}catch(_){}});
        var p=x.play();if(p&&p.catch)p.catch(function(){try{x.muted=true;var q=x.play();if(q&&q.catch)q.catch(function(){})}catch(_){}});
      }else if(!e.isIntersecting&&!x.paused)try{x.pause()}catch(_){}
    })},{threshold:[0,.35,.6,1]});
    wallIO.observe(v);
  }
  function syncWallMedia(){
    try{
      if(!(window.state&&window.state.view==='topics'))return;
      document.querySelectorAll('#auto-arcade-widget main video').forEach(wireWallVideo);
      document.querySelectorAll('#auto-arcade-widget main button').forEach(function(b){
        var t=(b.textContent||'').replace(/\s+/g,' ').trim().toLowerCase();
        if(t==='▶'||t==='play')b.style.setProperty('display','none','important');
      });
    }catch(_){}
  }
  syncBingoWallWhite();syncWallMedia();
  new MutationObserver(function(){syncBingoWallWhite();syncWallMedia()}).observe(document.documentElement,{childList:true,subtree:true});
  addEventListener('hashchange',function(){syncBingoWallWhite();syncWallMedia()});
  addEventListener('popstate',function(){syncBingoWallWhite();syncWallMedia()});
  addEventListener('click',function(){setTimeout(function(){syncBingoWallWhite();syncWallMedia()},0)},true);
})();

<?php
// Bingo deployment entrypoint: preserve the verified master file byte-for-byte.
// Performance bootstrap is injected externally so the 4.2MB master never needs rewriting.
$master = __DIR__ . '/BINGO_MASTER_CURRENT_VERIFIED.html';
$html = @file_get_contents($master);
// Canonical entry route: every fresh website load must hand off from the splash to Home.
// Do not restore a previous session's Topic/Wall route during bootstrap; navigation inside
// the running app still works normally after Home has opened.
if ($html !== false) {
  $html = str_replace(
    'aaResumeSavedRouteIfSafe();',
    'state.view="home";__aaRestoredScrollY=0;try{sessionStorage.removeItem("aa_current_route")}catch(e){};',
    $html
  );
}
if ($html === false) {
  http_response_code(500);
  echo 'Bingo is temporarily unavailable.';
  exit;
}
$early_guard = <<<'HTML'
<style id="bingo-prepaint-guard">html{background:#030713!important}body{visibility:hidden!important}#bingoSplash{visibility:visible!important}</style>
<script id="bingo-startup-hard-guard">
(function(){
  var released=false;
  /* Create the montage shell inside this parser-blocking head script. The old
     document body cannot paint first because body is still visibility:hidden. */
  /* Background-only placeholder - NOT a logo. This used to render a plain
     "Bingo" text wordmark here as a stand-in while the real body (and
     #bingoSplash's own approved artwork, further down in <body>) was still
     parsing. That text wordmark is a second, unapproved startup graphic -
     only the real #bingoSplash image is allowed to represent the opening
     montage. The actual "no white/stale flash before Home paints" job this
     element does is just holding the matching background color steady
     during that parse gap; the html{background} rule two lines up already
     does most of that work, this is only extra insurance for the instant
     before <body> itself starts painting. */
  function mountEarlySplash(){
    if(document.getElementById('bingoEarlySplash'))return;
    var s=document.createElement('div');s.id='bingoEarlySplash';
    s.style.cssText='position:fixed;inset:0;z-index:2147483647;background:#030713;visibility:visible!important';
    (document.documentElement||document).appendChild(s);
  }
  mountEarlySplash();
  /* releaseBingo() below used to only fire on the 2500ms absolute
     backstop or a persisted pageshow - there was no link to the real
     #bingoSplash's own ~1-1.2s exit (in the mother HTML's own early
     script), so #bingoEarlySplash sat on top of it - at a higher
     z-index - for the full 2.5s on every normal load, not just as a
     worst-case fallback. The mother HTML's early script removes
     'bingo-preload' from <html> the instant its own splash exit
     starts (~1000ms); that single class removal is already this
     app's one authoritative "app ready" signal, so poll for it here
     too and release the moment it happens. The 2500ms setTimeout
     further down stays as the true worst-case backstop if that
     signal is ever missed. */
  (function watchRealSplashExit(){
    var tries=0;
    var poll=setInterval(function(){
      tries++;
      if(!document.documentElement.classList.contains('bingo-preload')){
        clearInterval(poll);
        releaseBingo();
      }else if(tries>60){ // ~3s of polling at 50ms - the 2500ms backstop below covers the rest
        clearInterval(poll);
      }
    },50);
  })();
  // The old post-splash welcome mark is a second logo animation mounted on body,
  // outside #bingoSplash. Remove it immediately so splash effects cannot leak onto Home.
  try{
    var welcomeObserver=new MutationObserver(function(){
      var w=document.getElementById('bingoWelcomeMark');
      if(w)w.remove();
    });
    welcomeObserver.observe(document.documentElement,{childList:true,subtree:true});
    setTimeout(function(){try{welcomeObserver.disconnect()}catch(e){}},5000);
  }catch(e){}
  function releaseBingo(){
    if(released)return; released=true;
    try{
      document.documentElement.classList.remove('bingo-preload');
      var s=document.getElementById('bingoSplash');
      if(s){s.classList.add('hide');s.style.pointerEvents='none';setTimeout(function(){try{s.remove()}catch(e){}},700);}
      var es=document.getElementById('bingoEarlySplash');if(es)es.remove();
      document.documentElement.style.overflow='';
      if(document.body)document.body.style.overflow='';
      var pg=document.getElementById('bingo-prepaint-guard');if(pg)pg.remove();
    }catch(e){}
  }
  /* Absolute startup ceiling. Normal splash now clears itself around
     1.2s (compressed from 7s); this backstop only needs to be a short
     margin past that, not a distant worst case. */
  setTimeout(releaseBingo,2500);
  window.addEventListener('pageshow',function(e){if(e.persisted)setTimeout(releaseBingo,1200);},{once:true});
})();
</script>
HTML;
$head_pos = stripos($html, '<head');
if ($head_pos !== false && strpos($html, 'bingo-startup-hard-guard') === false) {
  // Inject immediately after the opening <head>, before legacy Home/feed CSS or DOM can paint.
  // This restores the pre-paint gate that prevents old screens flashing before the Bingo montage.
  $head_open_end = strpos($html, '>', $head_pos);
  if ($head_open_end !== false) $html = substr_replace($html, "\n".$early_guard."\n", $head_open_end + 1, 0);
}

$addons = "\n<script src=\"/assets/bingo-startup-route-splash-fix.js?v=20261003a\" defer></script>\n"
        . "<script src=\"/assets/bingo-performance-bootstrap.js?v=20261003c\" defer></script>\n"
        . "<script src=\"/assets/bingo-home-feed-clean-override.js?v=20261003j\" defer></script>\n"
        . "<script src=\"/assets/bingo-social-graph-addon.js?v=20261002e\" defer></script>\n";
if (strpos($html, 'bingo-home-feed-clean-override.js') === false) {
  $pos = strripos($html, '</body>');
  if ($pos !== false) $html = substr_replace($html, $addons, $pos, 0);
  else $html .= $addons;
}
// Allow browser revalidation instead of forcing a full 4.2MB re-download on every repeat visit.
// no-cache permits storage but requires validation; ETag lets unchanged responses return 304.
$etag = '"bingo-' . md5_file($master) . '-20261003f"';
header('Content-Type: text/html; charset=UTF-8');
header('Cache-Control: public, no-cache, max-age=0, must-revalidate');
header('ETag: ' . $etag);
if (isset($_SERVER['HTTP_IF_NONE_MATCH']) && trim($_SERVER['HTTP_IF_NONE_MATCH']) === $etag) {
  http_response_code(304);
  exit;
}
echo $html;

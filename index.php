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
<script id="bingo-startup-hard-guard">
(function(){
  var released=false;
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
      document.documentElement.style.overflow='';
      if(document.body)document.body.style.overflow='';
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
$head_pos = stripos($html, '</head>');
if ($head_pos !== false && strpos($html, 'bingo-startup-hard-guard') === false) {
  $html = substr_replace($html, "\n".$early_guard."\n", $head_pos, 0);
}

$addons = "\n<script src=\"/assets/bingo-performance-bootstrap.js?v=20261003c\" defer></script>\n"
        . "<script src=\"/assets/bingo-home-feed-clean-override.js?v=20261003f\" defer></script>\n"
        . "<script src=\"/assets/bingo-social-graph-addon.js?v=20261002e\" defer></script>\n";
if (strpos($html, 'bingo-home-feed-clean-override.js') === false) {
  $pos = strripos($html, '</body>');
  if ($pos !== false) $html = substr_replace($html, $addons, $pos, 0);
  else $html .= $addons;
}
// Allow browser revalidation instead of forcing a full 4.2MB re-download on every repeat visit.
// no-cache permits storage but requires validation; ETag lets unchanged responses return 304.
$etag = '"bingo-' . md5_file($master) . '-20261003a"';
header('Content-Type: text/html; charset=UTF-8');
header('Cache-Control: public, no-cache, max-age=0, must-revalidate');
header('ETag: ' . $etag);
if (isset($_SERVER['HTTP_IF_NONE_MATCH']) && trim($_SERVER['HTTP_IF_NONE_MATCH']) === $etag) {
  http_response_code(304);
  exit;
}
echo $html;

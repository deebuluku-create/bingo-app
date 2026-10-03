<?php
// Bingo deployment entrypoint: preserve the verified master file byte-for-byte.
// Performance bootstrap is injected externally so the 4.2MB master never needs rewriting.
$master = __DIR__ . '/BINGO_MASTER_CURRENT_VERIFIED.html';
$html = @file_get_contents($master);
if ($html === false) {
  http_response_code(500);
  echo 'Bingo is temporarily unavailable.';
  exit;
}
$addons = "\n<script src=\"/assets/bingo-performance-bootstrap.js?v=20261003b\" defer></script>\n"
        . "<script src=\"/assets/bingo-home-feed-clean-override.js?v=20261002e\" defer></script>\n"
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

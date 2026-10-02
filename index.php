<?php
// Bingo deployment entrypoint: preserve the verified master file byte-for-byte.
// Inject reviewed external addons ONLY before the document's final </body> tag.
$master = __DIR__ . '/BINGO_MASTER_CURRENT_VERIFIED.html';
$html = @file_get_contents($master);
if ($html === false) {
  http_response_code(500);
  echo 'Bingo is temporarily unavailable.';
  exit;
}
$addons = "\n<script src=\"/assets/bingo-home-feed-clean-override.js?v=20261002e\" defer></script>\n"
        . "<script src=\"/assets/bingo-social-graph-addon.js?v=20261002e\" defer></script>\n";
if (strpos($html, 'bingo-home-feed-clean-override.js') === false) {
  $pos = strripos($html, '</body>');
  if ($pos !== false) {
    $html = substr_replace($html, $addons, $pos, 0);
  } else {
    $html .= $addons;
  }
}
header('Content-Type: text/html; charset=UTF-8');
header('Cache-Control: no-cache, no-store, must-revalidate');
header('Pragma: no-cache');
header('Expires: 0');
echo $html;

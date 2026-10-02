<?php
// Bingo deployment entrypoint: preserve the verified master file byte-for-byte,
// inject only isolated reviewed addons at response time.
$master = __DIR__ . '/BINGO_MASTER_CURRENT_VERIFIED.html';
$html = @file_get_contents($master);
if ($html === false) {
  http_response_code(500);
  echo 'Bingo is temporarily unavailable.';
  exit;
}
$addons = "\n<script src=\"/assets/bingo-home-feed-clean-override.js?v=20261002d\" defer></script>\n"
        . "<script src=\"/assets/bingo-social-graph-addon.js?v=20261002d\" defer></script>\n";
if (strpos($html, 'bingo-home-feed-clean-override.js') === false) {
  $html = str_replace('</body>', $addons . '</body>', $html);
}
header('Content-Type: text/html; charset=UTF-8');
header('Cache-Control: no-cache, no-store, must-revalidate');
echo $html;

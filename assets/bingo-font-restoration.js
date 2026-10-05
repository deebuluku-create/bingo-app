/* Bingo approved font restoration — surgical bridge only.
   Scope: reuse the existing approved 50-font catalogue in comment/reply formatting.
   Post text + profile names already use AA_BINGO50_FONTS; Messenger keeps its
   existing larger searchable font studio. Ordinary forms are intentionally untouched. */
(function(){'use strict';
 let tries=0;
 function restore(){
  tries++;
  try{
   if(typeof AA_BINGO50_FONTS==='undefined'||typeof AA_COMMENT_FMT_FONTS==='undefined'){
    if(tries<120)setTimeout(restore,100);return;
   }
   if(AA_COMMENT_FMT_FONTS.__bingo50Restored)return;
   const list=AA_BINGO50_FONTS.map(f=>[f[1],f[0]]);
   AA_COMMENT_FMT_FONTS.splice(0,AA_COMMENT_FMT_FONTS.length,...list);
   Object.defineProperty(AA_COMMENT_FMT_FONTS,'__bingo50Restored',{value:true});
   /* Load only the web fonts already approved in the 50-font catalogue.
      This is delayed until after app boot so startup/layout remain unchanged. */
   const web=['Roboto','Open Sans','Lato','Montserrat','Poppins','Inter','Ubuntu','Nunito','Playfair Display','Cormorant Garamond','Cinzel','Bebas Neue','Oswald','Anton','Bungee','Pacifico','Dancing Script','Great Vibes','Allura','Sacramento','Parisienne','Alex Brush','Satisfy','Yellowtail','Lobster','Kaushan Script','Caveat','Permanent Marker','Courier Prime','Special Elite','UnifrakturCook'];
   web.forEach(name=>{try{if(typeof loadGoogleFont==='function')loadGoogleFont(name)}catch(e){}});
  }catch(e){console.warn('Bingo font restoration bridge:',e)}
 }
 if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',restore,{once:true});else restore();
})();
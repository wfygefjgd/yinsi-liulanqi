/// Injected JS for popup/ad light block, reader extract, and stitch.
class ReaderScripts {
  ReaderScripts._();

  /// Light popup / overlay blocker for normal browsing.
  static const popupBlock = r'''
(function(){
  if (window.__pbPopupBlock) return;
  window.__pbPopupBlock = true;
  try {
    window.open = function(){ return null; };
  } catch(e){}
  try {
    window.alert = function(){};
    window.confirm = function(){ return false; };
    window.prompt = function(){ return null; };
  } catch(e){}
  var hide = function(){
    try {
      var sel = [
        '[class*="popup"]','[class*="Popup"]','[id*="popup"]','[id*="Popup"]',
        '[class*="modal"]','[class*="Modal"]','[id*="modal"]',
        '[class*="advert"]','[class*="Advert"]','[class*="adsbox"]',
        '[id*="ads"]','[class*="ads-"]','[class*="ad-"]',
        '[class*="mask"]','[class*="overlay"]','[class*="dialog"]',
        'iframe[src*="ads"]','iframe[src*="doubleclick"]'
      ];
      document.querySelectorAll(sel.join(',')).forEach(function(el){
        try {
          var r = el.getBoundingClientRect();
          var fixed = getComputedStyle(el).position === 'fixed' || getComputedStyle(el).position === 'sticky';
          if (fixed || r.width > window.innerWidth * 0.5 || r.height > window.innerHeight * 0.4) {
            el.style.setProperty('display','none','important');
            el.style.setProperty('visibility','hidden','important');
            el.style.setProperty('pointer-events','none','important');
          }
        } catch(e){}
      });
      document.documentElement.style.overflow = 'auto';
      document.body && (document.body.style.overflow = 'auto');
    } catch(e){}
  };
  hide();
  setInterval(hide, 1200);
  document.addEventListener('click', function(ev){
    try {
      var t = ev.target;
      if (!t) return;
      var a = t.closest && t.closest('a');
      if (a && a.target === '_blank') a.target = '_self';
    } catch(e){}
  }, true);
})();
''';

  /// Extract main article HTML + next chapter URL heuristics.
  static const extractArticle = r'''
(function(){
  function textLen(el){
    return (el && (el.innerText || el.textContent) || '').replace(/\s+/g,' ').trim().length;
  }
  function score(el){
    if (!el) return 0;
    var t = textLen(el);
    var p = el.querySelectorAll('p').length;
    var a = el.querySelectorAll('a').length;
    var bad = 0;
    var cls = ((el.className||'')+' '+(el.id||'')).toLowerCase();
    if (/nav|menu|footer|header|comment|sidebar|recommend|ad|foot|tool/.test(cls)) bad += 800;
    return t + p * 40 - a * 8 - bad;
  }
  var cands = Array.prototype.slice.call(document.querySelectorAll(
    'article, #content, #Content, .content, .Content, #chaptercontent, #chapterContent, .chapter-content, .chapter_content, #BookText, #booktext, .read-content, .read_content, .novelcontent, .novel_content, main, .post-content, .entry-content, #nr1, #nr, .txt, #txt'
  ));
  if (!cands.length) {
    cands = Array.prototype.slice.call(document.querySelectorAll('div, section'));
  }
  var best = null, bestS = 0;
  cands.forEach(function(el){
    var s = score(el);
    if (s > bestS) { bestS = s; best = el; }
  });
  if (!best || bestS < 80) {
    best = document.body;
  }
  var title = (document.querySelector('h1') && document.querySelector('h1').innerText)
    || document.title || '';
  title = (title || '').trim();
  var html = best ? best.innerHTML : '';
  // next link
  var next = null;
  var links = Array.prototype.slice.call(document.querySelectorAll('a'));
  var nextRe = /下一[章页节回]|下[一页章]|next\s*chapter|next\s*page|›|»|>>/i;
  for (var i=0;i<links.length;i++){
    var a = links[i];
    var tx = (a.innerText || a.textContent || '').replace(/\s+/g,' ').trim();
    var href = a.href || '';
    if (!href || href.indexOf('javascript:')===0 || href === '#' ) continue;
    if (nextRe.test(tx) || /next|xia|下/.test((a.id||'')+(a.className||''))) {
      next = href;
      break;
    }
  }
  if (!next) {
    try {
      var u = new URL(location.href);
      var keys = ['page','p','Page','P','chapter','ch','pageid'];
      for (var k=0;k<keys.length;k++){
        var key = keys[k];
        if (u.searchParams.has(key)) {
          var n = parseInt(u.searchParams.get(key), 10);
          if (!isNaN(n)) {
            u.searchParams.set(key, String(n+1));
            next = u.toString();
            break;
          }
        }
      }
      if (!next) {
        var m = location.pathname.match(/(\d+)(\.\w+)?$/);
        if (m) {
          var num = parseInt(m[1],10)+1;
          next = location.origin + location.pathname.replace(/(\d+)(\.\w+)?$/, num + (m[2]||'')) + location.search;
        }
      }
    } catch(e){}
  }
  return JSON.stringify({ title: title, html: html, next: next || '', url: location.href, score: bestS });
})();
''';
}

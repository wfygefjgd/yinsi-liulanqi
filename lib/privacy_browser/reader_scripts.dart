/// Injected JS: ad/popup DOM cleanup + readability-style extract + next chapter.
class ReaderScripts {
  ReaderScripts._();

  /// Stronger runtime ad/popup/DOM cleanup (runs on page + interval).
  static const adAndPopupBlock = r'''
(function(){
  if (window.__pbAdBlockV2) return;
  window.__pbAdBlockV2 = true;

  try { window.open = function(){ return null; }; } catch(e){}
  try {
    window.alert = function(){};
    window.confirm = function(){ return false; };
    window.prompt = function(){ return null; };
  } catch(e){}

  var AD_RE = /doubleclick|googlesyndication|googleadservices|googletagmanager|pagead|adservice|adnxs|adsrvr|taboola|outbrain|criteo|scorecardresearch|cnzz|umeng|baidu\.com\/cpro|pos\.baidu|hm\.baidu|tanx\.com|popads|popcash|propeller|exoclick|juicyads|trafficjunky|adsterra|hilltopads|media\.net|moatads|hotjar|clarity\.ms|facebook\.net\/tr|analytics|prebid|adsbygoogle|adframe|adserver|partner\.googleadservices/i;

  function killNode(el){
    try {
      el.style.setProperty('display','none','important');
      el.style.setProperty('visibility','hidden','important');
      el.style.setProperty('pointer-events','none','important');
      el.setAttribute('data-pb-killed','1');
    } catch(e){}
  }

  function scrub(){
    try {
      document.querySelectorAll('script[src],iframe[src],img[src],link[href]').forEach(function(el){
        var s = el.src || el.href || '';
        if (s && AD_RE.test(s)) {
          try { el.remove(); } catch(e){ killNode(el); }
        }
      });

      var sel = [
        '[class*="popup"]','[id*="popup"]','[class*="Popup"]','[id*="Popup"]',
        '[class*="modal"]','[id*="modal"]','[class*="Modal"]',
        '[class*="advert"]','[class*="Advert"]','[class*="adsbox"]','[class*="ad-box"]',
        '[id*="ads"]','[class*="ads-"]','[class*="ad_"]','[class*=" ad "]',
        '[class*="mask"]','[class*="overlay"]','[class*="dialog"]',
        '[class*="float"]','[id*="float"]','[class*="banner"]',
        'iframe[src*="ads"]','iframe[src*="doubleclick"]','iframe[src*="googlesyndication"]',
        '[class*="gg"]','[id*="gg"]','[class*="guanggao"]'
      ];
      document.querySelectorAll(sel.join(',')).forEach(function(el){
        if (el.getAttribute('data-pb-killed')) return;
        try {
          var st = getComputedStyle(el);
          var r = el.getBoundingClientRect();
          var fixed = st.position === 'fixed' || st.position === 'sticky';
          var big = r.width > window.innerWidth * 0.45 || r.height > window.innerHeight * 0.35;
          var z = parseInt(st.zIndex,10) || 0;
          if (fixed || big || z > 1000) killNode(el);
        } catch(e){}
      });

      // full-screen fixed layers
      document.querySelectorAll('div,section,aside').forEach(function(el){
        if (el.getAttribute('data-pb-killed')) return;
        try {
          var st = getComputedStyle(el);
          if (st.position !== 'fixed' && st.position !== 'sticky') return;
          var r = el.getBoundingClientRect();
          if (r.width >= window.innerWidth * 0.9 && r.height >= window.innerHeight * 0.5) {
            var txt = (el.innerText||'').length;
            if (txt < 80) killNode(el);
          }
        } catch(e){}
      });

      document.documentElement.style.overflow = 'auto';
      if (document.body) {
        document.body.style.overflow = 'auto';
        document.body.style.position = 'static';
      }
    } catch(e){}
  }

  scrub();
  setInterval(scrub, 800);

  // MutationObserver for late ads
  try {
    var mo = new MutationObserver(function(){ scrub(); });
    mo.observe(document.documentElement, { childList:true, subtree:true });
  } catch(e){}

  document.addEventListener('click', function(ev){
    try {
      var a = ev.target && ev.target.closest && ev.target.closest('a');
      if (a && a.target === '_blank') a.target = '_self';
    } catch(e){}
  }, true);
})();
''';

  /// Legacy alias
  static const popupBlock = adAndPopupBlock;

  /// Readability-like extract: densest text block + next chapter heuristics.
  static const extractArticle = r'''
(function(){
  function textOf(el){
    return (el && (el.innerText || el.textContent) || '').replace(/\s+/g,' ').trim();
  }
  function textLen(el){ return textOf(el).length; }

  function isBad(el){
    if (!el || !el.tagName) return true;
    var t = el.tagName.toLowerCase();
    if (/^(script|style|nav|footer|header|aside|form|button|input|noscript|svg|iframe)$/.test(t)) return true;
    var cls = ((el.className&&el.className.toString)||'') + ' ' + (el.id||'');
    cls = cls.toLowerCase();
    if (/nav|menu|footer|header|comment|sidebar|recommend|related|share|social|tool|ad[-_]|ads|banner|popup|modal|copyright|breadcrumb|pager|pagination(?![-_]?content)/i.test(cls) && !/chapter|content|article|read|novel|book|txt|nr/.test(cls)) {
      return true;
    }
    return false;
  }

  function score(el){
    if (!el || isBad(el)) return -99999;
    var t = textLen(el);
    if (t < 40) return -1000;
    var p = el.querySelectorAll('p').length;
    var br = el.querySelectorAll('br').length;
    var a = el.querySelectorAll('a').length;
    var img = el.querySelectorAll('img').length;
    var linkDensity = a / Math.max(1, el.querySelectorAll('*').length);
    var s = t + p * 50 + br * 8 - a * 12 - img * 5;
    if (linkDensity > 0.35) s -= 400;
    var cls = ((el.className&&el.className.toString)||'') + ' ' + (el.id||'');
    cls = cls.toLowerCase();
    if (/chapter|content|article|read|novel|booktext|book_text|nr1|\bnr\b|txt|main|post/.test(cls)) s += 350;
    if (/list|item|card|grid|hot|rank/.test(cls)) s -= 200;
    return s;
  }

  var selectors = [
    'article','#content','#Content','.content','.Content',
    '#chaptercontent','#chapterContent','.chapter-content','.chapter_content',
    '#BookText','#booktext','.read-content','.read_content','.novelcontent','.novel_content',
    'main','.post-content','.entry-content','#nr1','#nr','.txt','#txt',
    '#js_content','.rich_media_content','#article','.article','.article-content',
    '#chapter','#Chapter','.chapter','.Chapter'
  ];
  var cands = [];
  selectors.forEach(function(sel){
    document.querySelectorAll(sel).forEach(function(el){ cands.push(el); });
  });
  if (cands.length < 3) {
    document.querySelectorAll('div,section').forEach(function(el){
      if (textLen(el) > 120) cands.push(el);
    });
  }

  var best = null, bestS = -1;
  cands.forEach(function(el){
    var s = score(el);
    if (s > bestS) { bestS = s; best = el; }
  });

  // climb to better parent if child is thin
  if (best && best.parentElement) {
    var parent = best.parentElement;
    var ps = score(parent);
    if (ps > bestS * 1.05 && ps - bestS > 80) {
      best = parent; bestS = ps;
    }
  }

  if (!best || bestS < 60) {
    best = document.body;
    bestS = score(best);
  }

  // clone and strip junk inside
  var clone = best.cloneNode(true);
  clone.querySelectorAll('script,style,iframe,ins,nav,footer,header,form,button,aside,noscript').forEach(function(n){ n.remove(); });
  clone.querySelectorAll('[class*="ad"],[id*="ad"],[class*="popup"],[class*="share"],[class*="recommend"],[class*="related"]').forEach(function(n){
    try { n.remove(); } catch(e){}
  });

  var title = '';
  var h1 = document.querySelector('h1');
  if (h1) title = textOf(h1);
  if (!title) {
    var h2 = best.querySelector('h1,h2,.title,.chapter-title,#title');
    if (h2) title = textOf(h2);
  }
  if (!title) title = (document.title||'').trim();
  // strip site name
  title = title.replace(/\s*[-_|].*$/,'').trim() || title;

  var html = clone.innerHTML || '';
  // collapse empty
  html = html.replace(/(<p>\s*<\/p>)+/gi, '');

  // next chapter
  var next = '';
  var nextRe = /下一[章页节回]|下[一页章]|next\s*(chapter|page)?|›|»|>>|下一页/i;
  var links = Array.prototype.slice.call(document.querySelectorAll('a[href]'));
  for (var i=0;i<links.length;i++){
    var a = links[i];
    var tx = textOf(a);
    var href = a.href || '';
    if (!href || href.indexOf('javascript:')===0 || href === '#' || href.indexOf('void')>=0) continue;
    if (nextRe.test(tx)) { next = href; break; }
    var idc = ((a.id||'')+(a.className||'')+(a.rel||'')).toLowerCase();
    if (/next|xia|下页|下章/.test(idc) && tx.length < 20) { next = href; break; }
  }
  if (!next) {
    try {
      var u = new URL(location.href);
      var keys = ['page','p','Page','P','chapter','ch','cid','pageid','index'];
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
        var m = location.pathname.match(/(.*?)(\d+)(\.\w+)?$/);
        if (m) {
          var num = parseInt(m[2],10)+1;
          next = location.origin + m[1] + num + (m[3]||'') + location.search;
        }
      }
    } catch(e){}
  }

  return JSON.stringify({
    title: title,
    html: html,
    next: next || '',
    url: location.href,
    score: bestS,
    textLen: textLen(clone)
  });
})();
''';
}

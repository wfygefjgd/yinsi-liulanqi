/// Injected JS: ad/popup cleanup, reader extract, element picker (with selector).
class ReaderScripts {
  ReaderScripts._();

  /// Stronger runtime ad/popup/DOM cleanup + early CSS cosmetic.
  static const adAndPopupBlock = r'''
(function(){
  if (window.__pbAdBlockV4) return;
  window.__pbAdBlockV4 = true;

  // Kill popup APIs hard
  try {
    window.open = function(){ return null; };
    window.showModalDialog = function(){ return null; };
  } catch(e){}
  try {
    window.alert = function(){};
    window.confirm = function(){ return false; };
    window.prompt = function(){ return null; };
  } catch(e){}
  try {
    // stop location hijack loops to ad hosts slightly
    var _ps = history.pushState.bind(history);
    var _rs = history.replaceState.bind(history);
    history.pushState = function(){ try { return _ps.apply(history, arguments); } catch(e){} };
    history.replaceState = function(){ try { return _rs.apply(history, arguments); } catch(e){} };
  } catch(e){}

  // Cosmetic CSS early — popups + common ad shells
  try {
    var st = document.createElement('style');
    st.id = 'pb-ad-css';
    st.textContent = [
      'iframe[src*="google"],iframe[src*="doubleclick"],iframe[src*="ads"],iframe[src*="adservice"],',
      'iframe[src*="ad."],iframe[id*="ad"],iframe[class*="ad"],iframe[src*="gdt."],iframe[src*="lianmeng"],',
      'ins.adsbygoogle,[id*="google_ads"],[class*="google-ad"],',
      '[class*="adsbox"],[id*="adsbox"],[class*="ad-box"],[class*="ad_box"],',
      '[class*="advert"],[id*="advert"],[class*="adbanner"],[id*="banner_ad"],',
      '[class*="popup"],[id*="popup"],[class*="pop-up"],[class*="popunder"],[class*="float-ad"],',
      '[id*="float"],[class*="floatads"],[class*="gg_"],[id*="gg_"],',
      '[class*="guanggao"],[id*="guanggao"],.ads,.ad,.AD,',
      '#ads,#ad,#AD,#googlead,#div_ad,',
      '[class*="mask"],[class*="overlay"][style*="z-index"],',
      '[class*="layui-layer"],[class*="layui-m"],.van-overlay,.mui-popup'
    ].join('') + '{display:none!important;visibility:hidden!important;height:0!important;max-height:0!important;overflow:hidden!important;pointer-events:none!important;opacity:0!important;}';
    (document.documentElement||document.head||document.body).appendChild(st);
  } catch(e){}

  function hostRoot(h){
    h = (h||'').toLowerCase().replace(/^www\./,'');
    var p = h.split('.');
    if (p.length <= 2) return h;
    return p.slice(-2).join('.');
  }
  var myRoot = hostRoot(location.hostname);

  // Same tab only; block clicks that leave site or hit ad hosts
  document.addEventListener('click', function(ev){
    try {
      var a = ev.target && ev.target.closest && ev.target.closest('a,area');
      if (!a) return;
      if (a.target === '_blank') a.target = '_self';
      var href = a.href || '';
      if (!href || href.indexOf('javascript:')===0) return;
      if (/doubleclick|googlesyndication|pagead|adservice|exoclick|popads|juicyads|gdt\.qq|lianmeng|pos\.baidu|hilltopads|adsterra|propeller|clickadu|trafficjunky/i.test(href)) {
        ev.preventDefault(); ev.stopPropagation(); return false;
      }
      try {
        var u = new URL(href, location.href);
        if (u.protocol.indexOf('http')===0 && hostRoot(u.hostname) !== myRoot) {
          // leave-site click: block (native layer also blocks)
          ev.preventDefault(); ev.stopPropagation(); return false;
        }
      } catch(e){}
    } catch(e){}
  }, true);

  var AD_RE = /doubleclick|googlesyndication|googleadservices|googletagmanager|pagead|adservice|adnxs|adsrvr|taboola|outbrain|criteo|scorecardresearch|cnzz|umeng|baidu\.com\/cpro|pos\.baidu|hm\.baidu|tanx\.com|popads|popcash|propeller|exoclick|juicyads|trafficjunky|adsterra|hilltopads|media\.net|moatads|hotjar|clarity\.ms|facebook\.net|analytics|prebid|adsbygoogle|adframe|adserver|partner\.googleadservices|gdt\.qq|lianmeng|mediav|union\.uc|pangolin|pglstatp|bytead|toutiao|snssdk|adkwai|adsystem|securepubads|googletagservices|fundingchoices|cookiebot|onesignal/i;

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
      document.querySelectorAll('script[src],iframe[src],img[src],link[href],video[src],source[src]').forEach(function(el){
        var s = el.src || el.href || '';
        if (s && AD_RE.test(s)) {
          try { el.remove(); } catch(e){ killNode(el); }
        }
      });

      var sel = [
        '[class*="popup"]','[id*="popup"]','[class*="Popup"]','[id*="Popup"]',
        '[class*="modal"]','[id*="modal"]','[class*="Modal"]',
        '[class*="advert"]','[class*="Advert"]','[class*="adsbox"]','[class*="ad-box"]',
        '[id*="ads"]','[class*="ads-"]','[class*="ad_"]',
        '[class*="mask"]','[class*="overlay"]','[class*="dialog"]',
        '[class*="float"]','[id*="float"]','[class*="banner"]',
        'iframe[src*="ads"]','iframe[src*="doubleclick"]','iframe[src*="googlesyndication"]',
        '[class*="gg"]','[id*="gg"]','[class*="guanggao"]','ins.adsbygoogle'
      ];
      document.querySelectorAll(sel.join(',')).forEach(function(el){
        if (el.getAttribute('data-pb-killed') || el.getAttribute('data-pb-user-hide')) return;
        try {
          var st = getComputedStyle(el);
          var r = el.getBoundingClientRect();
          var fixed = st.position === 'fixed' || st.position === 'sticky';
          var big = r.width > window.innerWidth * 0.4 || r.height > window.innerHeight * 0.3;
          var z = parseInt(st.zIndex,10) || 0;
          if (fixed || big || z > 800) killNode(el);
        } catch(e){}
      });

      document.querySelectorAll('div,section,aside').forEach(function(el){
        if (el.getAttribute('data-pb-killed') || el.getAttribute('data-pb-user-hide')) return;
        try {
          var st = getComputedStyle(el);
          if (st.position !== 'fixed' && st.position !== 'sticky') return;
          var r = el.getBoundingClientRect();
          if (r.width >= window.innerWidth * 0.85 && r.height >= window.innerHeight * 0.4) {
            var txt = (el.innerText||'').length;
            if (txt < 120) killNode(el);
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
  setInterval(scrub, 700);
  try {
    new MutationObserver(function(){ scrub(); })
      .observe(document.documentElement, { childList:true, subtree:true });
  } catch(e){}

  document.addEventListener('click', function(ev){
    try {
      var a = ev.target && ev.target.closest && ev.target.closest('a');
      if (a && a.target === '_blank') a.target = '_self';
    } catch(e){}
  }, true);
})();
''';

  static const popupBlock = adAndPopupBlock;

  /// Extract + pagination: numbered pages first, then 下一页, then 下一章.
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
    if (/nav|menu|footer|header|comment|sidebar|recommend|related|share|social|tool|ad[-_]|ads|banner|popup|modal|copyright|breadcrumb/i.test(cls) && !/chapter|content|article|read|novel|book|txt|nr|page/.test(cls)) {
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
    var linkDensity = a / Math.max(1, el.querySelectorAll('*').length);
    var s = t + p * 50 + br * 8 - a * 12;
    if (linkDensity > 0.35) s -= 400;
    var cls = ((el.className&&el.className.toString)||'') + ' ' + (el.id||'');
    cls = cls.toLowerCase();
    if (/chapter|content|article|read|novel|booktext|nr1|\bnr\b|txt|main|post/.test(cls)) s += 350;
    return s;
  }

  var selectors = [
    'article','#content','#Content','.content','.Content',
    '#chaptercontent','#chapterContent','.chapter-content','.chapter_content',
    '#BookText','#booktext','.read-content','.read_content','.novelcontent',
    'main','.post-content','.entry-content','#nr1','#nr','.txt','#txt',
    '#js_content','.rich_media_content','#article','.article-content','.chapter'
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
  if (best && best.parentElement) {
    var ps = score(best.parentElement);
    if (ps > bestS * 1.05 && ps - bestS > 80) { best = best.parentElement; bestS = ps; }
  }
  if (!best || bestS < 60) { best = document.body; bestS = score(best); }

  var clone = best.cloneNode(true);
  clone.querySelectorAll('script,style,iframe,ins,nav,footer,header,form,button,aside,noscript').forEach(function(n){ n.remove(); });
  clone.querySelectorAll('[class*="ad"],[id*="ad"],[class*="popup"],[class*="share"],[class*="recommend"]').forEach(function(n){
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
  title = title.replace(/\s*[-_|].*$/,'').trim() || title;
  var html = (clone.innerHTML || '').replace(/(<p>\s*<\/p>)+/gi, '');

  function isJs(href){
    return !href || href.indexOf('javascript:')===0 || href === '#' || href.indexOf('void')>=0;
  }
  var links = Array.prototype.slice.call(document.querySelectorAll('a[href]'));
  var nextPage = '';
  var nextChapter = '';
  var kind = '';

  // A) Numbered pager 1 2 3 4 5 — highest priority
  try {
    var pageNums = [];
    var seenN = {};
    links.forEach(function(a){
      var tx = textOf(a).replace(/\s+/g,'');
      if (!/^\d{1,3}$/.test(tx) || isJs(a.href)) return;
      var n = parseInt(tx,10);
      if (seenN[n]) return;
      seenN[n] = 1;
      pageNums.push({ n: n, href: a.href, el: a });
    });
    pageNums.sort(function(a,b){ return a.n - b.n; });
    if (pageNums.length >= 2) {
      var cur = 0;
      pageNums.forEach(function(p){
        try {
          var cls = ((p.el.className||'')+' '+(p.el.parentElement&&p.el.parentElement.className||'')).toLowerCase();
          if (/active|current|on|select|this|cur/.test(cls) || p.el.getAttribute('aria-current')) cur = p.n;
          // bold / strong current
          if (p.el.querySelector && p.el.querySelector('b,strong,em')) cur = p.n;
          var st = getComputedStyle(p.el);
          if (parseInt(st.fontWeight,10) >= 600 || st.fontWeight === 'bold') cur = p.n;
        } catch(e){}
      });
      try {
        var u0 = new URL(location.href);
        ['page','p','Page','P','pageid','index','pg'].forEach(function(k){
          if (u0.searchParams.has(k)) {
            var nn = parseInt(u0.searchParams.get(k),10);
            if (!isNaN(nn) && nn > 0) cur = nn;
          }
        });
        // path like /123_2.html chapter_page
        var mPath = location.pathname.match(/_(\d+)(\.\w+)?$/);
        if (mPath) {
          var pn = parseInt(mPath[1],10);
          if (!isNaN(pn) && pn < 50) cur = pn;
        }
      } catch(e){}
      if (!cur) {
        // find link matching current URL
        pageNums.forEach(function(p){
          try {
            if (p.href.split('#')[0] === location.href.split('#')[0]) cur = p.n;
          } catch(e){}
        });
      }
      if (!cur) cur = pageNums[0].n;
      for (var pi=0; pi<pageNums.length; pi++){
        if (pageNums[pi].n === cur + 1) {
          nextPage = pageNums[pi].href;
          kind = 'page';
          break;
        }
      }
    }
  } catch(e){}

  // B) 下一页 text (NOT 下一章)
  if (!nextPage) {
    for (var i=0;i<links.length;i++){
      var a = links[i];
      var tx = textOf(a);
      if (isJs(a.href)) continue;
      // strict page: 下一页 / 下页 — exclude 章
      if (/下一页|下页|next\s*page/i.test(tx) && !/章|节|回/.test(tx)) {
        nextPage = a.href; kind = 'page'; break;
      }
    }
  }

  // C) page= in URL
  if (!nextPage) {
    try {
      var u = new URL(location.href);
      var keys = ['page','p','Page','P','pageid','pg'];
      for (var k=0;k<keys.length;k++){
        if (u.searchParams.has(keys[k])) {
          var n = parseInt(u.searchParams.get(keys[k]), 10);
          if (!isNaN(n)) {
            u.searchParams.set(keys[k], String(n+1));
            nextPage = u.toString(); kind = 'page'; break;
          }
        }
      }
      // /xxx_2.html -> _3.html
      if (!nextPage) {
        var m = location.pathname.match(/^(.*_)(\d+)(\.\w+)?$/);
        if (m) {
          var num = parseInt(m[2],10);
          if (!isNaN(num) && num < 80) {
            nextPage = location.origin + m[1] + (num+1) + (m[3]||'') + location.search;
            kind = 'page';
          }
        }
      }
    } catch(e){}
  }

  // D) 下一章 ONLY if no next page
  if (!nextPage) {
    for (var j=0;j<links.length;j++){
      var a2 = links[j];
      var tx2 = textOf(a2);
      if (isJs(a2.href)) continue;
      if (/下一[章节回]|下[一]?章|next\s*chapter/i.test(tx2)) {
        nextChapter = a2.href; kind = 'chapter'; break;
      }
    }
  }

  var next = nextPage || nextChapter || '';
  if (nextPage) kind = 'page';
  else if (nextChapter) kind = 'chapter';

  return JSON.stringify({
    title: title,
    html: html,
    next: next || '',
    nextPage: nextPage || '',
    nextChapter: nextChapter || '',
    kind: kind,
    url: location.href,
    score: bestS,
    textLen: textLen(clone)
  });
})();
''';

  /// Click-to-hide; returns selector JSON via callHandler hideElement.
  static const elementPicker = r'''
(function(){
  if (window.__pbPickerOn) {
    window.__pbPickerOff && window.__pbPickerOff();
    return 'off';
  }
  window.__pbPickerOn = true;
  var hl = null;

  function cssEscape(s){
    try { return (window.CSS && CSS.escape) ? CSS.escape(s) : String(s).replace(/[^a-zA-Z0-9_-]/g,'\\$&'); }
    catch(e){ return String(s); }
  }

  function cssPath(el){
    if (!el || el.nodeType !== 1) return '';
    if (el.id) return '#' + cssEscape(el.id);
    var parts = [];
    var cur = el;
    for (var depth=0; depth<6 && cur && cur.nodeType===1 && cur !== document.body && cur !== document.documentElement; depth++){
      var name = cur.tagName.toLowerCase();
      if (cur.id) { parts.unshift('#' + cssEscape(cur.id)); break; }
      var parent = cur.parentElement;
      if (!parent) { parts.unshift(name); break; }
      var cls = '';
      try {
        if (cur.classList && cur.classList.length) {
          var c0 = cur.classList[0];
          if (c0 && c0.length < 40 && !/active|hover|open|show/.test(c0)) {
            cls = '.' + cssEscape(c0);
          }
        }
      } catch(e){}
      var same = parent.children ? Array.prototype.filter.call(parent.children, function(x){ return x.tagName === cur.tagName; }) : [];
      if (same.length > 1) {
        var idx = Array.prototype.indexOf.call(same, cur) + 1;
        parts.unshift(name + cls + ':nth-of-type(' + idx + ')');
      } else {
        parts.unshift(name + cls);
      }
      cur = parent;
    }
    return parts.join(' > ');
  }

  function outline(el, on){
    if (!el || !el.style) return;
    if (on) {
      el.setAttribute('data-pb-prev-outline', el.style.outline || '');
      el.style.outline = '2px solid #FF453A';
      el.style.outlineOffset = '2px';
    } else {
      el.style.outline = el.getAttribute('data-pb-prev-outline') || '';
      el.removeAttribute('data-pb-prev-outline');
    }
  }

  function move(ev){
    var x = ev.clientX, y = ev.clientY;
    if (ev.touches && ev.touches[0]) { x = ev.touches[0].clientX; y = ev.touches[0].clientY; }
    var t = document.elementFromPoint(x, y);
    if (!t || t === document.documentElement || t === document.body) return;
    if (hl && hl !== t) outline(hl, false);
    hl = t;
    outline(hl, true);
  }

  function click(ev){
    ev.preventDefault();
    ev.stopPropagation();
    var t = hl || ev.target;
    if (!t) return false;
    try {
      var el = t;
      for (var i=0;i<5 && el && el.parentElement;i++){
        var r = el.getBoundingClientRect();
        if (r.width * r.height > 2500) break;
        el = el.parentElement;
      }
      var sel = cssPath(el);
      el.style.setProperty('display','none','important');
      el.setAttribute('data-pb-user-hide','1');
      try {
        window.flutter_inappwebview.callHandler('hideElement', sel || '', location.href);
      } catch(e){}
    } catch(e){}
    return false;
  }

  function off(){
    window.__pbPickerOn = false;
    if (hl) outline(hl, false);
    document.removeEventListener('mousemove', move, true);
    document.removeEventListener('touchstart', move, true);
    document.removeEventListener('touchmove', move, true);
    document.removeEventListener('click', click, true);
  }
  window.__pbPickerOff = off;
  document.addEventListener('mousemove', move, true);
  document.addEventListener('touchstart', move, true);
  document.addEventListener('touchmove', move, true);
  document.addEventListener('click', click, true);
  return 'on';
})();
''';
}

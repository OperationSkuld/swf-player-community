// 临时校验：把 WebBrowserViewController 里的 sniffScript 抽出来跑 jsdom，
// 验证 oldswf 这类「真实文件写在脚本里 + 广告壳干扰」的页面排序是否准确。
const fs = require('fs');
const path = require('path');
const { JSDOM } = require('jsdom');

const swift = fs.readFileSync(path.join(__dirname, '..', 'SWFPlayer/Sources/WebBrowserViewController.swift'), 'utf8');
const marker = 'static let sniffScript = #"""';
const start = swift.indexOf(marker);
if (start < 0) { console.error('sniffScript not found'); process.exit(1); }
const bodyStart = start + marker.length;
const end = swift.indexOf('"""#', bodyStart);
if (end < 0) { console.error('sniffScript end not found'); process.exit(1); }
const js = swift.slice(bodyStart, end).trim();

const html = `<!doctype html><html><head>
<script src="/js/ads/banner_ad.swf.js"></script>
</head><body>
<div id="game"></div>
<script>
  var cfg = { "file": "/data/game_2024/74536.swf", "title": "demo" };
  function loadSwf(u){ var e=document.createElement('embed'); e.src=u; document.getElementById('game').appendChild(e); }
  loadSwf("/data/game_2024/74536.swf");
  var ad = "https://ads.example.com/banner/promo_300x250.swf";
</script>
<object data="/data/loader.swf" width="1" height="1"><param name="movie" value="/data/loader.swf"></object>
</body></html>`;

const dom = new JSDOM(html, { url: 'https://oldswf.com/game/74536', runScripts: 'outside-only' });
const win = dom.window;
win.webkit = { messageHandlers: { swfSniff: { postMessage: (m) => { win.__payload = m; } } } };
win.eval(js);

setTimeout(() => {
  const items = (win.__payload && win.__payload.items) || [];
  console.log('candidates:', items.length);
  items.forEach((it, i) => console.log(`  ${i + 1}. score=${it.s}  ${it.u}`));
  const first = items[0] && items[0].u || '';
  const ok = first.includes('/data/game_2024/74536.swf');
  const adFiltered = !items.some((it) => /banner|promo|ads\.example/.test(it.u));
  console.log('first is main game swf:', ok);
  console.log('ad urls filtered:', adFiltered);
  process.exit(ok && adFiltered ? 0 : 1);
}, 3200);

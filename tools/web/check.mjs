// 本地无头浏览器检查网页版：node tools/web/check.mjs <url> <下载目录> <截图目录>
// 依赖 puppeteer-core 与本机 Chrome（CHROME 环境变量，默认 /usr/bin/google-chrome）
import puppeteer from 'puppeteer-core';
import fs from 'fs';
const [url, dl, shots] = process.argv.slice(2);
fs.mkdirSync(dl, { recursive: true }); fs.mkdirSync(shots, { recursive: true });
const browser = await puppeteer.launch({ executablePath: process.env.CHROME || '/usr/bin/google-chrome', headless: 'new',
  args: ['--no-sandbox', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--window-size=1280,720'] });
const page = await browser.newPage();
await page.setViewport({ width: 1280, height: 720 });
const logs = [], errors = [];
page.on('console', m => { logs.push(m.text()); if (/SCRIPT ERROR|^ERROR|USER ERROR/.test(m.text()) || m.type() === 'error') errors.push(m.text()); });
page.on('pageerror', e => errors.push('pageerror: ' + e.message));
const cdp = await page.createCDPSession();
await cdp.send('Browser.setDownloadBehavior', { behavior: 'allow', downloadPath: dl });
let fail = 0; const ok = (c, m) => { console.log((c ? '  [PASS] ' : '  [FAIL] ') + m); if (!c) fail++; };
const t0 = Date.now();
await page.goto(url, { waitUntil: 'load' });
try { await page.waitForFunction('window.greybox && window.greybox.currentScene', { timeout: 90000 }); } catch (e) { await page.screenshot({ path: `${shots}/0_timeout.png` }); console.log('启动超时，控制台：\n' + logs.join('\n') + '\n错误：' + errors.join('\n')); process.exit(2); }
ok(true, `引擎启动完成（${((Date.now() - t0) / 1000).toFixed(1)} 秒）`);
const scene = () => page.evaluate('window.greybox.currentScene');
const waitScene = async (s, ms = 15000) => { const e = Date.now() + ms; while (Date.now() < e) { if ((await scene()) === s) return true; await new Promise(r => setTimeout(r, 200)); } return false; };
ok(await page.evaluate('!window.crossOriginIsolated') && await waitScene('res://scenes/village/village.tscn'), '无 COOP/COEP 头也能运行（单线程版），进入起程村');
await new Promise(r => setTimeout(r, 1500));
await page.screenshot({ path: `${shots}/1_opening.png` });
await new Promise(r => setTimeout(r, 10000)); // 第一次进入：开场旁白约 10 秒
await page.screenshot({ path: `${shots}/2_village.png` });
await page.mouse.click(640, 360); // 让画布获得焦点
await page.evaluate('window.greybox.startRun()');
ok(await waitScene('res://scenes/floor/floor.tscn'), '起程村 → 下潜第 1 层');
await new Promise(r => setTimeout(r, 800));
// 开放地图：楼层启动时打印“[map] 第 1 层：区块 30，生成 x ms，导航烘焙 y ms”
const mapLine = logs.find(l => l.includes('[map]')) || '';
const mm = mapLine.match(/区块 (\d+)，生成 ([\d.]+) ms，导航烘焙 ([\d.]+) ms/);
ok(mm && +mm[1] === 30 && +mm[2] + +mm[3] <= 800 && +mm[3] <= 600, `开放地图：${mapLine.trim() || '没有 [map] 日志'}（生成 + 烘焙 ≤ 800 ms，烘焙 ≤ 600 ms）`);
await page.keyboard.down('KeyD'); await new Promise(r => setTimeout(r, 900)); await page.keyboard.up('KeyD');
await page.keyboard.press('KeyJ'); await new Promise(r => setTimeout(r, 300));
await page.keyboard.press('Space'); await new Promise(r => setTimeout(r, 500));
await page.screenshot({ path: `${shots}/3_floor.png` });
// OM9 性能：主角周围 12 只敌人战斗，读逻辑帧时间（process + physics，指数平均）和 rAF 帧间隔
await page.evaluate('window.greybox.perfRing()');
await new Promise(r => setTimeout(r, 4000));
const raf = await page.evaluate(() => new Promise(res => { const ts = []; const f = t => { ts.push(t); if (ts.length < 121) requestAnimationFrame(f); else res(ts); }; requestAnimationFrame(f); }));
const gaps = raf.slice(1).map((t, i) => t - raf[i]).sort((a, b) => a - b);
const perf = await page.evaluate('[window.greybox.logicMs, window.greybox.enemies]');
const p95 = gaps[Math.floor(gaps.length * 0.95)]; const p99 = gaps[Math.floor(gaps.length * 0.99)];
ok(gaps[60] <= 17.5 && perf[1] >= 12, `OM9 主角周围 12 只敌人战斗（全层 ${perf[1]} 只，远处的休眠）：rAF 帧间隔中位数 ${gaps[60].toFixed(1)} ms，95% 分位 ${p95.toFixed(1)} ms、99% 分位 ${p99.toFixed(1)} ms（≤ 16.7 ms 即 60 帧；性能监视器 process+physics ${perf[0].toFixed(1)} ms，网页单线程下含渲染等待，仅供参考）`);
await page.keyboard.press('Backquote');
await new Promise(r => setTimeout(r, 800));
await page.screenshot({ path: `${shots}/4_debug_panel.png` });
await page.keyboard.press('Backquote');
await page.evaluate('window.greybox.selftestRow(); window.greybox.selftestRow(); window.greybox.downloadCsv()');
let csv = null; const e = Date.now() + 10000;
while (Date.now() < e && !csv) { const f = fs.readdirSync(dl).find(n => n === 'floors.csv'); if (f) csv = fs.readFileSync(`${dl}/${f}`, 'utf8'); else await new Promise(r => setTimeout(r, 300)); }
const lines = csv ? csv.trim().split('\n') : [];
ok(lines.length >= 3 && lines[0].startsWith('time,run_id,gen_no,depth,result,floor_sec'), `floors.csv 下载成功（${lines.length} 行）：${lines[1] || ''}`);
ok(errors.length === 0, `控制台无错误${errors.length ? '：' + errors.join(' | ') : ''}`);
fs.writeFileSync(`${shots}/console.log`, logs.join('\n'));
await browser.close();
console.log(fail ? `网页检查失败 ${fail} 项` : '网页检查全部通过');
process.exit(fail ? 1 : 0);

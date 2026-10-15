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
ok(await page.evaluate('!window.crossOriginIsolated') && await waitScene('res://scenes/camp.tscn'), '无 COOP/COEP 头也能运行（单线程版），进入营地');
await new Promise(r => setTimeout(r, 1500));
await page.screenshot({ path: `${shots}/1_camp.png` });
await page.mouse.click(640, 360); // 让画布获得焦点
await page.keyboard.press('Enter');
ok(await waitScene('res://scenes/dungeon.tscn'), '键盘回车：营地 → 迷宫');
await new Promise(r => setTimeout(r, 1000));
await page.screenshot({ path: `${shots}/2_dungeon.png` });
await page.keyboard.press('Backquote');
await new Promise(r => setTimeout(r, 800));
await page.screenshot({ path: `${shots}/3_debug_panel.png` });
await page.keyboard.press('Backquote');
await page.evaluate('window.greybox.selftestRow(); window.greybox.selftestRow(); window.greybox.downloadCsv()');
let csv = null; const e = Date.now() + 10000;
while (Date.now() < e && !csv) { const f = fs.readdirSync(dl).find(n => n.endsWith('.csv')); if (f) csv = fs.readFileSync(`${dl}/${f}`, 'utf8'); else await new Promise(r => setTimeout(r, 300)); }
const lines = csv ? csv.trim().split('\n') : [];
ok(lines.length >= 3 && lines[0].startsWith('time,run_id,depth,minigame'), `CSV 下载成功（${lines.length} 行）：${lines[1] || ''}`);
ok(errors.length === 0, `控制台无错误${errors.length ? '：' + errors.join(' | ') : ''}`);
fs.writeFileSync(`${shots}/console.log`, logs.join('\n'));
await browser.close();
console.log(fail ? `网页检查失败 ${fail} 项` : '网页检查全部通过');
process.exit(fail ? 1 : 0);

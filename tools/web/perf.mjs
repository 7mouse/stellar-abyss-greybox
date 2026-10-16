// 网页性能剖析：node tools/web/perf.mjs <url> <输出目录>
// 同一浏览器里依次测：空白页 rAF、村子、第 1 层清空敌人、第 1 层 12 只敌人战斗；每段 600 帧，打出中位/p95/p99 和引擎分段计时
import puppeteer from 'puppeteer-core';
import fs from 'fs';
const [url, out] = process.argv.slice(2);
fs.mkdirSync(out, { recursive: true });
const browser = await puppeteer.launch({ executablePath: process.env.CHROME || '/usr/bin/google-chrome', headless: 'new',
  args: ['--no-sandbox', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--window-size=1280,720'] });
const page = await browser.newPage();
await page.setViewport({ width: 1280, height: 720 });
const N = +(process.env.FRAMES || 600);
const rafStats = async () => {
  const ts = await page.evaluate(n => new Promise(res => { const a = []; const f = t => { a.push(t); if (a.length <= n) requestAnimationFrame(f); else res(a); }; requestAnimationFrame(f); }), N);
  const g = ts.slice(1).map((t, i) => t - ts[i]).sort((a, b) => a - b);
  const q = p => g[Math.min(g.length - 1, Math.floor(g.length * p))];
  const hist = {}; for (const x of g) { const k = Math.round(x / 16.67); hist[k] = (hist[k] || 0) + 1; }
  return { med: q(0.5), p95: q(0.95), p99: q(0.99), max: g[g.length - 1], over20: g.filter(x => x > 20).length, hist };
};
const fmt = (n, s) => `${n}: 中位 ${s.med.toFixed(1)} / p95 ${s.p95.toFixed(1)} / p99 ${s.p99.toFixed(1)} / 最大 ${s.max.toFixed(1)} ms，>20ms 帧 ${s.over20}/${N}，按 16.7ms 档 ${JSON.stringify(s.hist)}`;
const res = {};
await page.goto('about:blank');
res.blank = await rafStats(); console.log(fmt('空白页（同浏览器基线）', res.blank));
await page.goto(url, { waitUntil: 'load' });
await page.waitForFunction('window.greybox && window.greybox.currentScene === "res://scenes/village/village.tscn"', { timeout: 90000 });
await new Promise(r => setTimeout(r, 12000));
res.village = await rafStats(); console.log(fmt('村子', res.village));
await page.mouse.click(640, 360);
await page.evaluate('window.greybox.startRun()');
await page.waitForFunction('window.greybox.currentScene === "res://scenes/floor/floor.tscn"', { timeout: 30000 });
await new Promise(r => setTimeout(r, 2000));
const prof = async (label) => {
  await page.evaluate('window.greybox.profOn(true)');
  const s = await rafStats();
  await page.evaluate('window.greybox.profDump()');
  const fr = JSON.parse(await page.evaluate('window.greybox.prof'));
  await page.evaluate('window.greybox.profOn(false)');
  const sum = {}, mx = {}, steps = {}; let logic = [];
  for (const f of fr) { for (const k in f.us) { sum[k] = (sum[k] || 0) + f.us[k]; mx[k] = Math.max(mx[k] || 0, f.us[k]); } steps[f.steps] = (steps[f.steps] || 0) + 1; logic.push((f.proc + f.phys) / 1000); }
  logic.sort((a, b) => a - b);
  const sec = Object.keys(sum).sort((a, b) => sum[b] - sum[a]).map(k => `${k} ${(sum[k] / fr.length / 1000).toFixed(2)}ms(峰 ${(mx[k] / 1000).toFixed(1)})`).join('，');
  console.log(fmt(label, s));
  console.log(`    引擎逻辑 process+physics：中位 ${logic[logic.length >> 1].toFixed(1)} / p95 ${logic[Math.floor(logic.length * 0.95)].toFixed(1)} ms；每帧物理步数 ${JSON.stringify(steps)}；分段平均：${sec}`);
  fs.writeFileSync(`${out}/${label}.json`, JSON.stringify(fr));
  return s;
};
await page.evaluate('window.greybox.clearEnemies()');
await new Promise(r => setTimeout(r, 1000));
res.floor0 = await prof('第1层-无敌人');
await page.evaluate('window.greybox.startRun()');
await new Promise(r => setTimeout(r, 4000));
res.floor = await prof('第1层-原有巡逻怪');
await page.evaluate('window.greybox.perfRing()');
await new Promise(r => setTimeout(r, 3000));
res.fight = await prof('第1层-12只战斗');
fs.writeFileSync(`${out}/summary.json`, JSON.stringify(res, null, 1));
await browser.close();

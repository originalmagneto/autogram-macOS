// Capture a page viewport by viewport through Chrome DevTools Protocol.
// Usage: node cdp-shots.mjs <url> <outPrefix> <width> <height> <count> [step] [reducedMotion]
import { spawn } from 'node:child_process';
import { writeFile, mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const [url, prefix, w = '1440', h = '900', count = '6', stepArg, reduced] = process.argv.slice(2);
const width = Number(w), height = Number(h), step = Number(stepArg ?? height);
const port = 9300 + Math.floor(Math.random() * 500);
const profile = await mkdtemp(join(tmpdir(), 'cdp-'));
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', [
  '--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
  '--hide-scrollbars', '--mute-audio', '--autoplay-policy=no-user-gesture-required', 'about:blank',
], { stdio: 'ignore' });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws;
for (let i = 0; i < 50; i++) {
  try {
    const list = await (await fetch(`http://127.0.0.1:${port}/json`)).json();
    const page = list.find((t) => t.type === 'page');
    if (page) { ws = new WebSocket(page.webSocketDebuggerUrl); break; }
  } catch {}
  await sleep(200);
}
await new Promise((r) => ws.addEventListener('open', r));
let id = 0;
const pending = new Map();
ws.addEventListener('message', (e) => {
  const msg = JSON.parse(e.data);
  if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
});
const send = (method, params = {}) => new Promise((r) => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });

await send('Page.enable');
await send('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: width < 700 });
if (reduced) await send('Emulation.setEmulatedMedia', { features: [{ name: 'prefers-reduced-motion', value: 'reduce' }] });
await send('Page.navigate', { url });
await sleep(5000);
for (let i = 0; i < Number(count); i++) {
  await send('Runtime.evaluate', { expression: `window.scrollTo(0, ${i * step})` });
  await sleep(2200);
  const shot = await send('Page.captureScreenshot', { format: 'png' });
  await writeFile(`${prefix}-${String(i).padStart(2, '0')}.png`, Buffer.from(shot.result.data, 'base64'));
}
const total = await send('Runtime.evaluate', { expression: 'document.documentElement.scrollHeight', returnByValue: true });
console.log('scrollHeight', total.result.result.value);
ws.close();
chrome.kill();

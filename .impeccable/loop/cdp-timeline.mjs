// Capture the first viewport at given ms after load.
import { spawn } from 'node:child_process';
import { writeFile, mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const [url, prefix, w='1440', h='900', times='600,1200,2000,2800,3600,5000'] = process.argv.slice(2);
const port = 9950 + Math.floor(Math.random()*40);
const profile = await mkdtemp(join(tmpdir(), 'cdp-'));
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', ['--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`, '--hide-scrollbars', '--mute-audio', '--autoplay-policy=no-user-gesture-required', 'about:blank'], { stdio: 'ignore' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws; for (let i=0;i<50;i++){ try{ const l=await (await fetch(`http://127.0.0.1:${port}/json`)).json(); const p=l.find(t=>t.type==='page'); if(p){ws=new WebSocket(p.webSocketDebuggerUrl);break;} }catch{} await sleep(200); }
await new Promise(r=>ws.addEventListener('open',r)); let id=0; const pend=new Map();
ws.addEventListener('message',e=>{const m=JSON.parse(e.data); if(m.id&&pend.has(m.id)){pend.get(m.id)(m);pend.delete(m.id);}});
const send=(method,params={})=>new Promise(r=>{const i=++id;pend.set(i,r);ws.send(JSON.stringify({id:i,method,params}));});
await send('Page.enable'); await send('Emulation.setDeviceMetricsOverride',{width:+w,height:+h,deviceScaleFactor:1,mobile:+w<700});
const start = Date.now();
await send('Page.navigate',{url});
for (const t of times.split(',').map(Number)) {
  const wait = t - (Date.now() - start); if (wait > 0) await sleep(wait);
  const s = await send('Page.captureScreenshot',{format:'png'}); await writeFile(`${prefix}-${t}.png`, Buffer.from(s.result.data,'base64'));
}
ws.close(); chrome.kill();

// Capture interaction states: ZaKo gallery after "next", a playing video pill, a hover.
import { spawn } from 'node:child_process';
import { writeFile, mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const [url, prefix, w='1440', h='900'] = process.argv.slice(2);
const port = 9800 + Math.floor(Math.random()*150);
const profile = await mkdtemp(join(tmpdir(), 'cdp-'));
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', ['--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`, '--hide-scrollbars', '--mute-audio', '--autoplay-policy=no-user-gesture-required', 'about:blank'], { stdio: 'ignore' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws; for (let i=0;i<50;i++){ try{ const l=await (await fetch(`http://127.0.0.1:${port}/json`)).json(); const p=l.find(t=>t.type==='page'); if(p){ws=new WebSocket(p.webSocketDebuggerUrl);break;} }catch{} await sleep(200); }
await new Promise(r=>ws.addEventListener('open',r)); let id=0; const pend=new Map();
ws.addEventListener('message',e=>{const m=JSON.parse(e.data); if(m.id&&pend.has(m.id)){pend.get(m.id)(m);pend.delete(m.id);}});
const send=(method,params={})=>new Promise(r=>{const i=++id;pend.set(i,r);ws.send(JSON.stringify({id:i,method,params}));});
const shot=async(n)=>{const s=await send('Page.captureScreenshot',{format:'png'}); await writeFile(`${prefix}-${n}.png`,Buffer.from(s.result.data,'base64'));};
const ev=async(x)=>(await send('Runtime.evaluate',{expression:x,returnByValue:true,awaitPromise:true})).result.result.value;
await send('Page.enable'); await send('Emulation.setDeviceMetricsOverride',{width:+w,height:+h,deviceScaleFactor:1,mobile:+w<700});
await send('Page.navigate',{url}); await sleep(4000);
const G = (n) => `document.querySelectorAll('[data-gallery]')[${n}]`;
for (const [n, name] of [[0, 'signing'], [1, 'zako']]) {
  await ev(`${G(n)}.scrollIntoView({block:'center'})`); await sleep(3500); await shot(`${name}-gallery-1`);
  await ev(`${G(n)}.querySelectorAll('.arrow')[1].click()`); await sleep(3800); await shot(`${name}-gallery-2`);
  await ev(`${G(n)}.querySelectorAll('.arrow')[1].click()`); await sleep(3800); await shot(`${name}-gallery-3`);
  const last = await ev(`${G(n)}.querySelectorAll('.tile').length`);
  if (last > 3) { await ev(`${G(n)}.querySelectorAll('.arrow')[1].click()`); await sleep(3800); await shot(`${name}-gallery-4`); }
}
const r = await ev(`(()=>{const b=document.querySelector('.download .primary').getBoundingClientRect();return [b.x+b.width/2,b.y+b.height/2]})()`);
await ev(`document.querySelector('.download').scrollIntoView({block:'center'})`); await sleep(1200);
const r2 = await ev(`(()=>{const b=document.querySelector('.download .primary').getBoundingClientRect();return [b.x+b.width/2,b.y+b.height/2]})()`);
await send('Input.dispatchMouseEvent',{type:'mouseMoved',x:r2[0],y:r2[1]}); await sleep(700); await shot('download-hover');
ws.close(); chrome.kill();

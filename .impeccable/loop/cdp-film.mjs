// Record the page as a video: the intro on load, then a smooth scroll to the end.
import { spawn } from 'node:child_process';
import { writeFile, mkdtemp, mkdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
const [url, dir, w='1440', h='900'] = process.argv.slice(2);
await mkdir(dir, { recursive: true });
const port = 9600 + Math.floor(Math.random()*90);
const profile = await mkdtemp(join(tmpdir(), 'cdp-'));
const chrome = spawn('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome', ['--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`, '--hide-scrollbars', '--mute-audio', '--autoplay-policy=no-user-gesture-required', 'about:blank'], { stdio: 'ignore' });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let ws; for (let i=0;i<50;i++){ try{ const l=await (await fetch(`http://127.0.0.1:${port}/json`)).json(); const p=l.find(t=>t.type==='page'); if(p){ws=new WebSocket(p.webSocketDebuggerUrl);break;} }catch{} await sleep(200); }
await new Promise(r=>ws.addEventListener('open',r)); let id=0; const pend=new Map();
const frames=[]; 
ws.addEventListener('message',e=>{const m=JSON.parse(e.data); if(m.method==='Page.screencastFrame'){ frames.push({t:Date.now(), data:m.params.data}); ws.send(JSON.stringify({id:++id,method:'Page.screencastFrameAck',params:{sessionId:m.params.sessionId}})); } if(m.id&&pend.has(m.id)){pend.get(m.id)(m);pend.delete(m.id);}});
const send=(method,params={})=>new Promise(r=>{const i=++id;pend.set(i,r);ws.send(JSON.stringify({id:i,method,params}));});
const ev=async(x)=>(await send('Runtime.evaluate',{expression:x,returnByValue:true,awaitPromise:true})).result.result.value;
await send('Page.enable'); await send('Emulation.setDeviceMetricsOverride',{width:+w,height:+h,deviceScaleFactor:1,mobile:+w<700});
await send('Page.startScreencast',{format:'jpeg',quality:82,everyNthFrame:1});
await send('Page.navigate',{url});
await sleep(6500);
const total = await ev('document.documentElement.scrollHeight - innerHeight');
// scroll smoothly, pausing at the flow diagram and the galleries
const stops = await ev(`[...document.querySelectorAll('[data-flows] .stage-area, [data-gallery]')].map(e => e.getBoundingClientRect().top + scrollY - innerHeight*0.25)`);
let y = 0; const speed = +w < 700 ? 9 : 12;
while (y < total) {
  y = Math.min(total, y + speed);
  await ev(`window.scrollTo(0, ${y})`);
  await sleep(16);
  if (stops.some(s => Math.abs(s - y) < speed)) await sleep(3200);
}
await sleep(1500);
await send('Page.stopScreencast');
let i = 0; const t0 = frames[0].t;
const list = [];
for (const f of frames) { const n = String(i++).padStart(5,'0'); await writeFile(`${dir}/${n}.jpg`, Buffer.from(f.data,'base64')); list.push(`file '${dir}/${n}.jpg'\nduration ${(0.001).toFixed(3)}`); }
// timing file for ffmpeg concat
let out = ''; for (let k=0;k<frames.length;k++){ const d = k<frames.length-1 ? (frames[k+1].t-frames[k].t)/1000 : 0.04; out += `file '${dir}/${String(k).padStart(5,'0')}.jpg'\nduration ${d.toFixed(3)}\n`; }
await writeFile(`${dir}/list.txt`, out);
console.log('frames', frames.length, 'seconds', ((frames.at(-1).t - t0)/1000).toFixed(1));
ws.close(); chrome.kill();

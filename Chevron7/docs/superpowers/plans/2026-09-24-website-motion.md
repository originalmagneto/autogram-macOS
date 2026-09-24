# Website motion with HyperFrames: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Five muted loops and one ~50 s product video, rendered with HyperFrames in Slovak and English, placed on chevron7.slovensko.app.

**Architecture:** A separate `website/motion/` package holds one HyperFrames project per piece, shared tokens, fonts and GSAP, the on-screen copy per language and the captures. `render.mjs` stages shared assets into each project, runs `hyperframes check`, renders both languages, adds `+faststart`, writes a poster (final frame) and a provenance sidecar into `website/public/media/`, and enforces the size budgets. The site gains a `MotionLoop.astro` component and a video dialog in the hero.

**Tech Stack:** HyperFrames 0.8.72 (`npx hyperframes`), GSAP 3.14.2, FFmpeg 9 (`ffmpeg`, `ffprobe`), Node 26 (`node --test`), Astro 7.

**Spec:** `Chevron7/docs/superpowers/specs/2026-09-24-website-motion-design.md` (app repository). Read it before any task.

## Global Constraints

- Every claim stays true of the shipped app; copy comes from `website/src/i18n/{sk,en}.ts` or short derivations of it (`PRODUCT.md` rule).
- App visuals are real captures with synthetic sample documents; where none exists, a diagram or typography, never invented UI.
- The final, locked state is the default: every loop's first and last frame show the locked state, and the poster is that frame. Loops play only under the `.motion` class on `<html>` and never under reduced motion.
- Colors: Midnight `#0a0b1a`, text `#f5f5f7` / `#d6dbe5` / `#bec8dc` / `#8d97ab`, lines `rgb(214 219 229 / 0.14)` and `/ 0.32`, one amber light `#ffb23e` with `#ffd27a` as its hot core. No other hue.
- Font: Atkinson Hyperlegible Next from `website/public/fonts/` via `@font-face` (HyperFrames lint requires a shipped font for a named family).
- Loops: 1280 x 720, 24 fps, 6 to 12 s, about 600 kB per language. Product video: 1920 x 1080, 30 fps, about 50 s, about 6 MB per language.
- Outputs: `website/public/media/<name>-<lang>.mp4`, `<name>-<lang>-poster.jpg`, `<name>-<lang>.mp4.json` with `{ "prompt": ..., "createdAt": ... }` (existing sidecar convention; `public/.assetsignore` keeps `*.json` unpublished).
- No sound in any render. `HYPERFRAMES_NO_TELEMETRY=1` for every HyperFrames command.
- No em dashes anywhere (repository hard rule).
- The owner's app state is untouched after captures: EZZK mode back to Produkcia, the owner's advocate profile active, no register row written.
- Nothing is pushed to `chevron7-website` `main` (it deploys at once) before the owner approves a local preview.

---

### Task 1: The `motion/` package and its render pipeline

**Files:**
- Create: `website/motion/package.json`
- Create: `website/motion/.gitignore`
- Create: `website/motion/lib.mjs`
- Create: `website/motion/lib.test.mjs`
- Create: `website/motion/render.mjs`
- Create: `website/motion/shared/frame.css`
- Create: `website/motion/copy/sk.json`
- Create: `website/motion/copy/en.json`
- Create: `website/motion/README.md`

**Interfaces:**
- Produces: `PIECES` (array of `{ name, width, height, fps, budgetKB, crf, media, captures }`), `outputPaths(name, lang, mediaDir) -> { video, poster, sidecar }`, `sidecar(piece, lang, hyperframesVersion, now) -> { prompt, createdAt }`, `withinBudget(bytes, piece) -> boolean`, `variablesFor(copy, name) -> object`. Every composition later reads its copy through variables whose ids are the keys of `copy/<lang>.json[<name>]`.

- [ ] **Step 1: Package and ignore file**

`website/motion/package.json`:

```json
{
  "name": "chevron7-motion",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "node --test",
    "render": "HYPERFRAMES_NO_TELEMETRY=1 node render.mjs"
  },
  "devDependencies": {
    "gsap": "3.14.2",
    "hyperframes": "0.8.72"
  }
}
```

`website/motion/.gitignore` (staged copies and render scratch never enter git):

```
node_modules/
compositions/*/assets/
compositions/*/renders/
.render/
```

- [ ] **Step 2: Write the failing tests**

`website/motion/lib.test.mjs`:

```js
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PIECES, outputPaths, sidecar, withinBudget, variablesFor } from './lib.mjs';

test('every piece has the spec size, rate and budget', () => {
  const loops = PIECES.filter((p) => p.name.startsWith('loop-'));
  assert.deepEqual(loops.map((p) => p.name).sort(),
    ['loop-local', 'loop-way-card', 'loop-way-mobile', 'loop-way-safari', 'loop-zako']);
  for (const p of loops) assert.deepEqual([p.width, p.height, p.fps, p.budgetKB], [1280, 720, 24, 600]);
  const product = PIECES.find((p) => p.name === 'product');
  assert.deepEqual([product.width, product.height, product.fps, product.budgetKB], [1920, 1080, 30, 6144]);
});

test('outputs land in public/media with the language in the name', () => {
  assert.deepEqual(outputPaths('loop-zako', 'sk', '/m'), {
    video: '/m/loop-zako-sk.mp4',
    poster: '/m/loop-zako-sk-poster.jpg',
    sidecar: '/m/loop-zako-sk.mp4.json',
  });
});

test('the sidecar says what the file is and when it was made', () => {
  const piece = PIECES.find((p) => p.name === 'loop-zako');
  const s = sidecar(piece, 'en', '0.8.72', new Date('2026-09-24T12:00:00Z'));
  assert.equal(s.createdAt, '2026-09-24T12:00:00.000Z');
  assert.match(s.prompt, /HyperFrames 0\.8\.72/);
  assert.match(s.prompt, /loop-zako/);
  assert.match(s.prompt, /English/);
  assert.match(s.prompt, /real captures/);
});

test('budgets are kilobytes of 1024 bytes', () => {
  const piece = { budgetKB: 600 };
  assert.equal(withinBudget(600 * 1024, piece), true);
  assert.equal(withinBudget(600 * 1024 + 1, piece), false);
});

test('variables are the piece entry of the copy file', () => {
  const copy = { 'loop-way-card': { step1: 'Vložte kartu' } };
  assert.deepEqual(variablesFor(copy, 'loop-way-card'), { step1: 'Vložte kartu' });
  assert.throws(() => variablesFor(copy, 'loop-zako'), /no copy for loop-zako/);
});
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `cd website/motion && npm install && npm test`
Expected: FAIL, `Cannot find module './lib.mjs'`.

- [ ] **Step 4: Write `lib.mjs`**

```js
// Pure helpers of the render pipeline, tested by lib.test.mjs.
import { join } from 'node:path';

const loop = (name, extra = {}) => ({
  name, width: 1280, height: 720, fps: 24, budgetKB: 600, crf: 30, media: [], captures: [], ...extra,
});

export const PIECES = [
  loop('loop-way-card'),
  loop('loop-way-mobile'),
  loop('loop-way-safari'),
  loop('loop-local'),
  loop('loop-zako', { captures: ['zako-scan.png', 'zako-clause.png', 'zako-pin.png'] }),
  {
    name: 'product', width: 1920, height: 1080, fps: 30, budgetKB: 6144, crf: 27,
    media: ['panel.mp4', 'mobile.mp4', 'stamp.mp4', 'zako-review.mp4', 'hero-icon.mp4'],
    captures: ['zako-scan.png', 'zako-clause.png', 'zako-pin.png'],
  },
];

export const LANGS = { sk: 'Slovak', en: 'English' };

export function outputPaths(name, lang, mediaDir) {
  const base = join(mediaDir, `${name}-${lang}`);
  return { video: `${base}.mp4`, poster: `${base}-poster.jpg`, sidecar: `${base}.mp4.json` };
}

export function sidecar(piece, lang, hyperframesVersion, now = new Date()) {
  return {
    prompt: `Rendered with HyperFrames ${hyperframesVersion} from website/motion/compositions/${piece.name} (${LANGS[lang]} copy): `
      + 'site typography and diagrams; app pictures are real captures of Chevron7 with synthetic sample documents, never generated',
    createdAt: now.toISOString(),
  };
}

export function withinBudget(bytes, piece) {
  return bytes <= piece.budgetKB * 1024;
}

export function variablesFor(copy, name) {
  if (!copy[name]) throw new Error(`no copy for ${name}`);
  return copy[name];
}
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `cd website/motion && npm test`
Expected: PASS, 5 tests.

- [ ] **Step 6: Shared frame tokens**

`website/motion/shared/frame.css` (staged into each project as `assets/frame.css`; font paths are relative to `assets/`):

```css
@font-face { font-family: 'Atkinson Hyperlegible Next'; font-weight: 400; src: url('fonts/atkinson-hyperlegible-next-latin-ext-400-normal.woff2') format('woff2'); }
@font-face { font-family: 'Atkinson Hyperlegible Next'; font-weight: 600; src: url('fonts/atkinson-hyperlegible-next-latin-ext-600-normal.woff2') format('woff2'); }
@font-face { font-family: 'Atkinson Hyperlegible Next'; font-weight: 700; src: url('fonts/atkinson-hyperlegible-next-latin-ext-700-normal.woff2') format('woff2'); }

:root {
  --ink-0: #0a0b1a;
  --text-0: #f5f5f7;
  --text-1: #d6dbe5;
  --text-2: #bec8dc;
  --text-3: #8d97ab;
  --line: rgb(214 219 229 / 0.14);
  --line-strong: rgb(214 219 229 / 0.32);
  --amber: #ffb23e;
  --amber-hot: #ffd27a;
}

html, body { margin: 0; background: var(--ink-0); }
body { color: var(--text-0); font-family: 'Atkinson Hyperlegible Next', sans-serif; }
#root { position: relative; width: 100%; height: 100%; overflow: hidden; background: var(--ink-0); }
.label { font-size: 30px; font-weight: 600; letter-spacing: -0.01em; color: var(--text-1); }
.caption { font-size: 22px; color: var(--text-3); }
.stroke { fill: none; stroke: var(--line-strong); stroke-width: 3; stroke-linecap: round; stroke-linejoin: round; }
.amber { stroke: var(--amber); }
```

- [ ] **Step 7: Copy files**

`website/motion/copy/sk.json`:

```json
{
  "loop-way-card": { "step1": "Vložte kartu", "step2": "Zadajte PIN", "step3": "Podpísané" },
  "loop-way-mobile": { "step1": "QR kód na Macu", "step2": "Autogram v mobile", "step3": "Podpísané" },
  "loop-way-safari": { "step1": "Portál žiada podpis", "step2": "Potvrďte v Chevron7", "step3": "Podpísané" },
  "loop-local": {
    "mac": "Dokument ostáva na Macu",
    "tsa": "Časová pečiatka: iba odtlačok",
    "eu": "Overenie: zoznamy EÚ",
    "relay": "Podpis mobilom: zmazané do 24 h"
  },
  "loop-zako": {
    "scan": "Sken listiny", "review": "Kontrola prvkov", "clause": "Doložka",
    "mqc": "Mandátny certifikát", "number": "Evidenčné číslo z EZZK", "cezzk": "CEZZK: spracovaný"
  },
  "product": {
    "l1": "Kvalifikovaný podpis. Natívne na Macu.",
    "l2": "Podpíšte PDF kartou eID, I.CA alebo preukazom SAK.",
    "l3": "Bez čítačky: iPhone prečíta občiansky preukaz cez NFC.",
    "l4": "Podpisujte priamo na slovensko.sk.",
    "l5": "Zaručená konverzia: od skenu po záznam v CEZZK.",
    "l6": "Dokumenty ostávajú na vašom Macu. Zadarmo, open source.",
    "url": "chevron7.slovensko.app"
  }
}
```

`website/motion/copy/en.json`:

```json
{
  "loop-way-card": { "step1": "Insert the card", "step2": "Enter the PIN", "step3": "Signed" },
  "loop-way-mobile": { "step1": "QR code on the Mac", "step2": "Autogram v mobile", "step3": "Signed" },
  "loop-way-safari": { "step1": "The portal asks to sign", "step2": "Confirm in Chevron7", "step3": "Signed" },
  "loop-local": {
    "mac": "The document stays on the Mac",
    "tsa": "Timestamp: only a fingerprint",
    "eu": "Validation: EU trusted lists",
    "relay": "Mobile signing: deleted within 24 h"
  },
  "loop-zako": {
    "scan": "Scan", "review": "Element review", "clause": "Clause",
    "mqc": "Mandate certificate", "number": "Evidence number from EZZK", "cezzk": "CEZZK: processed"
  },
  "product": {
    "l1": "Qualified signatures. Native on the Mac.",
    "l2": "Sign PDFs with an eID, I.CA or SAK card.",
    "l3": "No reader: an iPhone reads the ID card over NFC.",
    "l4": "Sign right on slovensko.sk.",
    "l5": "Guaranteed conversion: from the scan to a record in CEZZK.",
    "l6": "Your documents stay on your Mac. Free, open source.",
    "url": "chevron7.slovensko.app"
  }
}
```

- [ ] **Step 8: Write `render.mjs`**

```js
// Renders every piece (or the ones named on the command line) in both languages into
// ../public/media. Usage: npm run render [-- loop-zako product]
import { execFileSync } from 'node:child_process';
import { cpSync, mkdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PIECES, LANGS, outputPaths, sidecar, withinBudget, variablesFor } from './lib.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const site = join(here, '..');
const mediaDir = join(site, 'public', 'media');
const scratch = join(here, '.render');
const env = { ...process.env, HYPERFRAMES_NO_TELEMETRY: '1' };
const run = (cmd, args, cwd = here) => execFileSync(cmd, args, { cwd, env, stdio: 'inherit' });
const read = (cmd, args, cwd = here) => execFileSync(cmd, args, { cwd, env, encoding: 'utf8' });

const version = JSON.parse(readFileSync(join(here, 'node_modules/hyperframes/package.json'), 'utf8')).version;
const wanted = process.argv.slice(2);
const pieces = wanted.length ? PIECES.filter((p) => wanted.includes(p.name)) : PIECES;
if (wanted.length && pieces.length !== wanted.length) throw new Error(`unknown piece in ${wanted.join(', ')}`);

function stage(piece, project) {
  const assets = join(project, 'assets');
  rmSync(assets, { recursive: true, force: true });
  mkdirSync(join(assets, 'fonts'), { recursive: true });
  cpSync(join(here, 'shared/frame.css'), join(assets, 'frame.css'));
  cpSync(join(here, 'node_modules/gsap/dist/gsap.min.js'), join(assets, 'gsap.min.js'));
  for (const w of [400, 600, 700]) {
    const f = `atkinson-hyperlegible-next-latin-ext-${w}-normal.woff2`;
    cpSync(join(site, 'public/fonts', f), join(assets, 'fonts', f));
  }
  for (const m of piece.media) cpSync(join(mediaDir, m), join(assets, m));
  for (const c of piece.captures) cpSync(join(here, 'captures', c), join(assets, c));
}

mkdirSync(scratch, { recursive: true });
for (const piece of pieces) {
  const project = join(here, 'compositions', piece.name);
  stage(piece, project);
  run('npx', ['hyperframes', 'check'], project);
  for (const lang of Object.keys(LANGS)) {
    const copy = JSON.parse(readFileSync(join(here, 'copy', `${lang}.json`), 'utf8'));
    const vars = join(scratch, `${piece.name}-${lang}.json`);
    writeFileSync(vars, JSON.stringify(variablesFor(copy, piece.name)));
    const raw = join(scratch, `${piece.name}-${lang}.raw.mp4`);
    run('npx', ['hyperframes', 'render', '--quality', 'delivery', '--fps', String(piece.fps),
      '--crf', String(piece.crf), '--strict-variables', '--variables-file', vars, '--output', raw], project);
    const out = outputPaths(piece.name, lang, mediaDir);
    // Muted, web-ready: no audio stream, moov atom first so playback starts before the download ends.
    run('ffmpeg', ['-y', '-v', 'error', '-i', raw, '-an', '-c:v', 'copy', '-movflags', '+faststart', out.video]);
    run('ffmpeg', ['-y', '-v', 'error', '-sseof', '-0.05', '-i', out.video, '-frames:v', '1', '-q:v', '3', out.poster]);
    writeFileSync(out.sidecar, JSON.stringify(sidecar(piece, lang, version), null, 2));
    const bytes = statSync(out.video).size;
    const probe = read('ffprobe', ['-v', 'error', '-select_streams', 'v:0', '-show_entries',
      'stream=width,height,r_frame_rate', '-of', 'csv=p=0', out.video]).trim();
    console.log(`${piece.name}-${lang}: ${(bytes / 1024).toFixed(0)} kB, ${probe}`);
    if (!withinBudget(bytes, piece)) throw new Error(`${piece.name}-${lang} is over its ${piece.budgetKB} kB budget`);
  }
}
```

- [ ] **Step 9: README**

`website/motion/README.md`:

```md
# Motion

Loops and the product video of chevron7.slovensko.app, rendered with HyperFrames. Design:
`Chevron7/docs/superpowers/specs/2026-09-24-website-motion-design.md` in the app repository.

- `compositions/<name>/index.html`: one HyperFrames project per piece; copy comes in as variables.
- `copy/sk.json`, `copy/en.json`: every on-screen line.
- `captures/`: real Chevron7 captures (synthetic sample documents), each with a `.json` sidecar.
- `shared/frame.css`: the site's tokens and font for the frame.

    npm install
    npm test
    npm run render                 # everything
    npm run render -- loop-zako    # one piece

Outputs go to `../public/media/<name>-<lang>.{mp4,-poster.jpg,.mp4.json}`. Needs Node 22+ and FFmpeg.
```

- [ ] **Step 10: Commit** (website repository)

```bash
cd website && git add motion/package.json motion/package-lock.json motion/.gitignore motion/lib.mjs motion/lib.test.mjs motion/render.mjs motion/shared motion/copy motion/README.md
git commit -m "chore(motion): HyperFrames render pipeline for loops and the product video"
```

---

### Task 2: Loop "Kartou" (`loop-way-card`)

**Files:**
- Create: `website/motion/compositions/loop-way-card/index.html`
- Output: `website/public/media/loop-way-card-{sk,en}.mp4`, posters, sidecars

**Interfaces:**
- Consumes: `assets/frame.css`, `assets/gsap.min.js` (staged by `render.mjs`), variables `step1`, `step2`, `step3`.
- Produces: the loop pattern every later loop follows: 8 s; locked state at 0 s and from 6.8 s to the end; build-up between.

- [ ] **Step 1: Write the composition**

```html
<!doctype html>
<html lang="sk" data-composition-variables='[
  {"id":"step1","type":"string","label":"Step 1","default":"Vložte kartu"},
  {"id":"step2","type":"string","label":"Step 2","default":"Zadajte PIN"},
  {"id":"step3","type":"string","label":"Step 3","default":"Podpísané"}
]'>
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=1280, height=720" />
  <link rel="stylesheet" href="assets/frame.css" />
  <script src="assets/gsap.min.js"></script>
  <style>
    .scene { position: absolute; inset: 0; display: grid; grid-template-columns: 1fr 1fr 1fr; align-items: center; justify-items: center; padding: 0 96px; }
    .step { display: grid; justify-items: center; gap: 28px; }
    svg { width: 220px; height: 160px; overflow: visible; }
    .pin i { display: inline-block; width: 22px; height: 22px; margin: 0 7px; border-radius: 50%; border: 3px solid var(--line-strong); }
    .pin i.on { background: var(--text-0); border-color: var(--text-0); }
    .rail { position: absolute; left: 213px; right: 213px; top: 300px; height: 3px; background: var(--line); }
    .rail span { display: block; height: 100%; width: 100%; background: var(--line-strong); transform-origin: left; }
  </style>
</head>
<body>
  <div id="root" data-composition-id="loop-way-card" data-start="0" data-width="1280" data-height="720" data-duration="8">
    <div class="rail" aria-hidden="true"><span id="rail"></span></div>
    <section class="scene clip" data-start="0" data-duration="8">
      <div class="step" id="s1">
        <svg viewBox="0 0 220 160"><rect class="stroke" x="40" y="70" width="140" height="70" rx="10" />
          <rect id="card" class="stroke" x="70" y="10" width="80" height="110" rx="8" /></svg>
        <div class="label" data-var-text="step1">Vložte kartu</div>
      </div>
      <div class="step" id="s2">
        <svg viewBox="0 0 220 160"><foreignObject x="0" y="55" width="220" height="50">
          <div class="pin" xmlns="http://www.w3.org/1999/xhtml"><i></i><i></i><i></i><i></i><i></i><i></i></div></foreignObject></svg>
        <div class="label" data-var-text="step2">Zadajte PIN</div>
      </div>
      <div class="step" id="s3">
        <svg viewBox="0 0 220 160"><circle id="seal" class="stroke amber" cx="110" cy="80" r="56" />
          <path id="tick" class="stroke amber" d="M84 82 L103 100 L138 62" /></svg>
        <div class="label" data-var-text="step3">Podpísané</div>
      </div>
    </section>
  </div>
  <script>
    const tl = gsap.timeline({ paused: true });
    const dots = gsap.utils.toArray('.pin i');
    // 0 to 0.6 s: the locked state (first frame = last frame) fades back to the start.
    tl.fromTo('#rail', { scaleX: 1 }, { scaleX: 0, duration: 0.5, ease: 'power2.in' }, 0.1)
      .fromTo('#s2, #s3', { opacity: 1 }, { opacity: 0.25, duration: 0.5 }, 0.1)
      .fromTo('#seal, #tick', { opacity: 1 }, { opacity: 0, duration: 0.4 }, 0.1)
      .set(dots, { className: '' }, 0.6)
      // 0.8 to 2.4 s: the card slides into the reader.
      .fromTo('#card', { y: -60 }, { y: 0, duration: 1.2, ease: 'power3.out' }, 0.8)
      .fromTo('#rail', { scaleX: 0 }, { scaleX: 0.5, duration: 0.8, ease: 'power2.inOut' }, 2.0)
      .to('#s2', { opacity: 1, duration: 0.4 }, 2.4);
    // 2.8 to 4.6 s: six PIN dots fill.
    dots.forEach((d, i) => tl.set(d, { className: 'on' }, 2.8 + i * 0.3));
    tl.fromTo('#rail', { scaleX: 0.5 }, { scaleX: 1, duration: 0.8, ease: 'power2.inOut' }, 4.8)
      .to('#s3', { opacity: 1, duration: 0.4 }, 5.3)
      // 5.6 to 6.8 s: the amber seal draws and locks; held to the end.
      .fromTo('#seal', { opacity: 1, strokeDasharray: 352, strokeDashoffset: 352 }, { strokeDashoffset: 0, duration: 0.8, ease: 'power2.out' }, 5.6)
      .fromTo('#tick', { opacity: 1, strokeDasharray: 80, strokeDashoffset: 80 }, { strokeDashoffset: 0, duration: 0.5, ease: 'power2.out' }, 6.2);
    window.__timelines['loop-way-card'] = tl;
  </script>
</body>
</html>
```

- [ ] **Step 2: Check and snapshot**

Run: `cd website/motion && npm run render -- loop-way-card` (it runs `hyperframes check` first and stops on any finding).
Expected: `check` reports 0 findings. If it reports `gsap_css_transform_conflict` or `font_family_without_font_face`, fix the named element; do not suppress.

Then: `cd compositions/loop-way-card && HYPERFRAMES_NO_TELEMETRY=1 npx hyperframes snapshot --at 0,1.5,3.8,6,7.9`
Expected: frames at 0 and 7.9 are identical in content (locked: rail full, six filled dots, amber seal and tick); 1.5 shows the card mid-slide; 3.8 shows three or four filled dots. Read each PNG and confirm no text is cut and no hue other than the palette appears.

- [ ] **Step 3: Render and check the outputs**

Run: `cd website/motion && npm run render -- loop-way-card`
Expected: two lines `loop-way-card-sk: <n> kB, 1280,720,24/1` and `loop-way-card-en: ...`, each under 600 kB; `public/media/loop-way-card-{sk,en}-poster.jpg` show the locked state with Slovak and English labels.

- [ ] **Step 4: Commit**

```bash
cd website && git add motion/compositions/loop-way-card/index.html public/media/loop-way-card-*
git commit -m "feat(motion): loop for signing with a card"
```

---

### Task 3: Loop "Mobilom" (`loop-way-mobile`)

**Files:**
- Create: `website/motion/compositions/loop-way-mobile/index.html`
- Output: `website/public/media/loop-way-mobile-{sk,en}.*`

**Interfaces:**
- Consumes: staged assets; variables `step1`, `step2`, `step3`.

- [ ] **Step 1: Write the composition**

Same frame, rail and three-step grid as `loop-way-card` (repeat its `<head>` styles verbatim); pictures and timeline:

```html
<!doctype html>
<html lang="sk" data-composition-variables='[
  {"id":"step1","type":"string","label":"Step 1","default":"QR kód na Macu"},
  {"id":"step2","type":"string","label":"Step 2","default":"Autogram v mobile"},
  {"id":"step3","type":"string","label":"Step 3","default":"Podpísané"}
]'>
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=1280, height=720" />
  <link rel="stylesheet" href="assets/frame.css" />
  <script src="assets/gsap.min.js"></script>
  <style>
    .scene { position: absolute; inset: 0; display: grid; grid-template-columns: 1fr 1fr 1fr; align-items: center; justify-items: center; padding: 0 96px; }
    .step { display: grid; justify-items: center; gap: 28px; }
    svg { width: 220px; height: 160px; overflow: visible; }
    .rail { position: absolute; left: 213px; right: 213px; top: 300px; height: 3px; background: var(--line); }
    .rail span { display: block; height: 100%; width: 100%; background: var(--line-strong); transform-origin: left; }
    .qr rect { fill: var(--text-1); }
  </style>
</head>
<body>
  <div id="root" data-composition-id="loop-way-mobile" data-start="0" data-width="1280" data-height="720" data-duration="8">
    <div class="rail" aria-hidden="true"><span id="rail"></span></div>
    <section class="scene clip" data-start="0" data-duration="8">
      <div class="step" id="s1">
        <svg viewBox="0 0 220 160"><rect class="stroke" x="30" y="10" width="160" height="110" rx="10" />
          <g class="qr" id="qr" transform="translate(80 35)">
            <rect x="0" y="0" width="18" height="18" /><rect x="42" y="0" width="18" height="18" /><rect x="0" y="42" width="18" height="18" />
            <rect x="24" y="24" width="12" height="12" /><rect x="42" y="42" width="8" height="8" /><rect x="24" y="6" width="8" height="8" /></g>
          <path class="stroke" d="M90 120 L80 146 H140 L130 120" /></svg>
        <div class="label" data-var-text="step1">QR kód na Macu</div>
      </div>
      <div class="step" id="s2">
        <svg viewBox="0 0 220 160"><rect id="phone" class="stroke" x="80" y="10" width="60" height="120" rx="12" />
          <path id="w1" class="stroke" d="M156 60 Q166 70 156 80" /><path id="w2" class="stroke" d="M166 50 Q182 70 166 90" />
          <path id="w3" class="stroke" d="M176 40 Q198 70 176 100" /></svg>
        <div class="label" data-var-text="step2">Autogram v mobile</div>
      </div>
      <div class="step" id="s3">
        <svg viewBox="0 0 220 160"><circle id="seal" class="stroke amber" cx="110" cy="80" r="56" />
          <path id="tick" class="stroke amber" d="M84 82 L103 100 L138 62" /></svg>
        <div class="label" data-var-text="step3">Podpísané</div>
      </div>
    </section>
  </div>
  <script>
    const tl = gsap.timeline({ paused: true });
    tl.fromTo('#rail', { scaleX: 1 }, { scaleX: 0, duration: 0.5, ease: 'power2.in' }, 0.1)
      .fromTo('#s2, #s3', { opacity: 1 }, { opacity: 0.25, duration: 0.5 }, 0.1)
      .fromTo('#seal, #tick', { opacity: 1 }, { opacity: 0, duration: 0.4 }, 0.1)
      .fromTo('#qr', { opacity: 1 }, { opacity: 0, duration: 0.3 }, 0.1)
      // 0.8 to 1.8 s: the QR code appears on the Mac.
      .to('#qr', { opacity: 1, duration: 0.6 }, 0.8)
      .fromTo('#rail', { scaleX: 0 }, { scaleX: 0.5, duration: 0.8, ease: 'power2.inOut' }, 2.0)
      .to('#s2', { opacity: 1, duration: 0.4 }, 2.4)
      // 2.8 to 4.6 s: NFC waves pulse three times (finite repeat, deterministic).
      .fromTo(['#w1', '#w2', '#w3'], { opacity: 0.15 }, { opacity: 1, duration: 0.3, stagger: 0.15, repeat: 2, yoyo: true }, 2.8)
      .fromTo('#rail', { scaleX: 0.5 }, { scaleX: 1, duration: 0.8, ease: 'power2.inOut' }, 4.8)
      .to('#s3', { opacity: 1, duration: 0.4 }, 5.3)
      .fromTo('#seal', { opacity: 1, strokeDasharray: 352, strokeDashoffset: 352 }, { strokeDashoffset: 0, duration: 0.8, ease: 'power2.out' }, 5.6)
      .fromTo('#tick', { opacity: 1, strokeDasharray: 80, strokeDashoffset: 80 }, { strokeDashoffset: 0, duration: 0.5, ease: 'power2.out' }, 6.2)
      .set(['#w1', '#w2', '#w3'], { opacity: 1 }, 6.8);
    window.__timelines['loop-way-mobile'] = tl;
  </script>
</body>
</html>
```

- [ ] **Step 2: Check, snapshot at `0,1.2,3.4,6,7.9`, render, verify** exactly as Task 2 Steps 2 and 3 with `loop-way-mobile`. Expected: 0 s and 7.9 s identical (QR shown, waves full, seal locked).

- [ ] **Step 3: Commit**

```bash
cd website && git add motion/compositions/loop-way-mobile/index.html public/media/loop-way-mobile-*
git commit -m "feat(motion): loop for signing with a phone"
```

---

### Task 4: Loop "V Safari" (`loop-way-safari`)

**Files:**
- Create: `website/motion/compositions/loop-way-safari/index.html`
- Output: `website/public/media/loop-way-safari-{sk,en}.*`

**Interfaces:**
- Consumes: staged assets; variables `step1`, `step2`, `step3`.

- [ ] **Step 1: Write the composition**

```html
<!doctype html>
<html lang="sk" data-composition-variables='[
  {"id":"step1","type":"string","label":"Step 1","default":"Portál žiada podpis"},
  {"id":"step2","type":"string","label":"Step 2","default":"Potvrďte v Chevron7"},
  {"id":"step3","type":"string","label":"Step 3","default":"Podpísané"}
]'>
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=1280, height=720" />
  <link rel="stylesheet" href="assets/frame.css" />
  <script src="assets/gsap.min.js"></script>
  <style>
    .scene { position: absolute; inset: 0; display: grid; grid-template-columns: 1fr 1fr 1fr; align-items: center; justify-items: center; padding: 0 96px; }
    .step { display: grid; justify-items: center; gap: 28px; }
    svg { width: 220px; height: 160px; overflow: visible; }
    .rail { position: absolute; left: 213px; right: 213px; top: 300px; height: 3px; background: var(--line); }
    .rail span { display: block; height: 100%; width: 100%; background: var(--line-strong); transform-origin: left; }
    .fill { fill: var(--text-0); }
  </style>
</head>
<body>
  <div id="root" data-composition-id="loop-way-safari" data-start="0" data-width="1280" data-height="720" data-duration="8">
    <div class="rail" aria-hidden="true"><span id="rail"></span></div>
    <section class="scene clip" data-start="0" data-duration="8">
      <div class="step" id="s1">
        <svg viewBox="0 0 220 160"><rect class="stroke" x="20" y="10" width="180" height="130" rx="10" />
          <path class="stroke" d="M20 36 H200" /><rect id="ask" class="stroke" x="60" y="80" width="100" height="30" rx="15" /></svg>
        <div class="label" data-var-text="step1">Portál žiada podpis</div>
      </div>
      <div class="step" id="s2">
        <svg viewBox="0 0 220 160"><rect id="panel" class="stroke" x="50" y="20" width="120" height="110" rx="14" />
          <rect id="confirm" class="fill" x="72" y="92" width="76" height="24" rx="12" /></svg>
        <div class="label" data-var-text="step2">Potvrďte v Chevron7</div>
      </div>
      <div class="step" id="s3">
        <svg viewBox="0 0 220 160"><circle id="seal" class="stroke amber" cx="110" cy="80" r="56" />
          <path id="tick" class="stroke amber" d="M84 82 L103 100 L138 62" /></svg>
        <div class="label" data-var-text="step3">Podpísané</div>
      </div>
    </section>
  </div>
  <script>
    const tl = gsap.timeline({ paused: true });
    tl.fromTo('#rail', { scaleX: 1 }, { scaleX: 0, duration: 0.5, ease: 'power2.in' }, 0.1)
      .fromTo('#s2, #s3', { opacity: 1 }, { opacity: 0.25, duration: 0.5 }, 0.1)
      .fromTo('#seal, #tick', { opacity: 1 }, { opacity: 0, duration: 0.4 }, 0.1)
      // 0.8 to 1.8 s: the portal's sign button pulses once.
      .fromTo('#ask', { scale: 1, transformOrigin: '50% 50%' }, { scale: 1.08, duration: 0.3, repeat: 1, yoyo: true }, 0.8)
      .fromTo('#rail', { scaleX: 0 }, { scaleX: 0.5, duration: 0.8, ease: 'power2.inOut' }, 2.0)
      // 2.4 to 3.4 s: the Chevron7 panel rises in.
      .fromTo('#s2', { opacity: 0.25 }, { opacity: 1, duration: 0.4 }, 2.4)
      .fromTo('#panel', { y: 24 }, { y: 0, duration: 0.8, ease: 'power3.out' }, 2.4)
      // 3.8 to 4.4 s: "Potvrdiť" is pressed.
      .fromTo('#confirm', { scale: 1, transformOrigin: '50% 50%' }, { scale: 0.92, duration: 0.15, repeat: 1, yoyo: true }, 3.9)
      .fromTo('#rail', { scaleX: 0.5 }, { scaleX: 1, duration: 0.8, ease: 'power2.inOut' }, 4.8)
      .to('#s3', { opacity: 1, duration: 0.4 }, 5.3)
      .fromTo('#seal', { opacity: 1, strokeDasharray: 352, strokeDashoffset: 352 }, { strokeDashoffset: 0, duration: 0.8, ease: 'power2.out' }, 5.6)
      .fromTo('#tick', { opacity: 1, strokeDasharray: 80, strokeDashoffset: 80 }, { strokeDashoffset: 0, duration: 0.5, ease: 'power2.out' }, 6.2);
    window.__timelines['loop-way-safari'] = tl;
  </script>
</body>
</html>
```

- [ ] **Step 2: Check, snapshot at `0,1,3,4,7.9`, render, verify** as Task 2 Steps 2 and 3 with `loop-way-safari`.

- [ ] **Step 3: Commit**

```bash
cd website && git add motion/compositions/loop-way-safari/index.html public/media/loop-way-safari-*
git commit -m "feat(motion): loop for signing on state portals"
```

---

### Task 5: Loop "Dokumenty ostávajú na Macu" (`loop-local`)

**Files:**
- Create: `website/motion/compositions/loop-local/index.html`
- Output: `website/public/media/loop-local-{sk,en}.*`

**Interfaces:**
- Consumes: staged assets; variables `mac`, `tsa`, `eu`, `relay`.

- [ ] **Step 1: Write the composition**

A Mac outline at the left holds the document for the whole loop. Three lanes run right: a short fingerprint travels to "timestamp", a question to "EU lists", and for mobile an encrypted envelope reaches the relay whose 24-hour bar drains. 10 s; locked state (all three lanes drawn, relay bar empty with its label) at 0 s and from 8.6 s.

```html
<!doctype html>
<html lang="sk" data-composition-variables='[
  {"id":"mac","type":"string","label":"Mac","default":"Dokument ostáva na Macu"},
  {"id":"tsa","type":"string","label":"TSA","default":"Časová pečiatka: iba odtlačok"},
  {"id":"eu","type":"string","label":"EU","default":"Overenie: zoznamy EÚ"},
  {"id":"relay","type":"string","label":"Relay","default":"Podpis mobilom: zmazané do 24 h"}
]'>
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=1280, height=720" />
  <link rel="stylesheet" href="assets/frame.css" />
  <script src="assets/gsap.min.js"></script>
  <style>
    .mac { position: absolute; left: 90px; top: 170px; width: 360px; display: grid; justify-items: center; gap: 24px; }
    .mac svg { width: 360px; height: 260px; }
    .lanes { position: absolute; left: 500px; right: 80px; top: 150px; display: grid; gap: 70px; }
    .lane { display: grid; grid-template-columns: 320px 1fr; align-items: center; gap: 28px; }
    .lane svg { width: 320px; height: 40px; overflow: visible; }
    .token { fill: var(--amber); }
    .bar { fill: var(--line-strong); }
  </style>
</head>
<body>
  <div id="root" data-composition-id="loop-local" data-start="0" data-width="1280" data-height="720" data-duration="10">
    <section class="clip" data-start="0" data-duration="10" style="position:absolute;inset:0">
      <div class="mac">
        <svg viewBox="0 0 360 260"><rect class="stroke" x="10" y="10" width="340" height="200" rx="14" />
          <path class="stroke" d="M130 210 L110 250 H250 L230 210" />
          <rect class="stroke amber" x="140" y="50" width="80" height="110" rx="6" />
          <path class="stroke" d="M156 80 H204 M156 100 H204 M156 120 H190" /></svg>
        <div class="label" data-var-text="mac">Dokument ostáva na Macu</div>
      </div>
      <div class="lanes">
        <div class="lane"><svg viewBox="0 0 320 40"><path class="stroke" d="M0 20 H320" /><rect id="hash" class="token" x="0" y="12" width="40" height="16" rx="8" /></svg>
          <div class="label" data-var-text="tsa">Časová pečiatka: iba odtlačok</div></div>
        <div class="lane"><svg viewBox="0 0 320 40"><path class="stroke" d="M0 20 H320" /><circle id="ask" class="token" cx="10" cy="20" r="9" /></svg>
          <div class="label" data-var-text="eu">Overenie: zoznamy EÚ</div></div>
        <div class="lane"><svg viewBox="0 0 320 40"><path class="stroke" d="M0 20 H200" /><rect id="env" class="token" x="0" y="10" width="30" height="20" rx="3" />
          <rect class="stroke" x="210" y="4" width="110" height="32" rx="6" /><rect id="ttl" class="bar" x="214" y="8" width="102" height="24" rx="4" /></svg>
          <div class="label" data-var-text="relay">Podpis mobilom: zmazané do 24 h</div></div>
      </div>
    </section>
  </div>
  <script>
    const tl = gsap.timeline({ paused: true });
    // Locked frame: tokens rest at their destinations and the relay bar is empty.
    tl.fromTo('#hash', { x: 280 }, { x: 0, duration: 0.01 }, 0.4)
      .fromTo('#ask', { x: 300 }, { x: 0, duration: 0.01 }, 0.4)
      .fromTo('#env', { x: 170 }, { x: 0, duration: 0.01 }, 0.4)
      .fromTo('#ttl', { scaleX: 0, transformOrigin: 'left center' }, { scaleX: 0, duration: 0.01 }, 0.4)
      // 0.8 to 2.6 s: only the fingerprint leaves for the timestamp authority.
      .to('#hash', { x: 280, duration: 1.8, ease: 'power2.inOut' }, 0.8)
      // 2.8 to 4.6 s: a question goes to the EU trusted lists.
      .to('#ask', { x: 300, duration: 1.8, ease: 'power2.inOut' }, 2.8)
      // 4.8 to 6.2 s: for mobile signing the encrypted envelope reaches the relay.
      .to('#env', { x: 170, duration: 1.4, ease: 'power2.inOut' }, 4.8)
      .to('#ttl', { scaleX: 1, duration: 0.4 }, 6.2)
      // 6.6 to 8.6 s: the 24-hour bar drains.
      .to('#ttl', { scaleX: 0, duration: 2.0, ease: 'none' }, 6.6);
    window.__timelines['loop-local'] = tl;
  </script>
</body>
</html>
```

- [ ] **Step 2: Check, snapshot at `0,1.7,3.7,6.4,9.9`, render, verify** as Task 2 Steps 2 and 3 with `loop-local`. Expected: 0 s and 9.9 s identical; English labels fit their lane (the longest is "Mobile signing: deleted within 24 h").

- [ ] **Step 3: Commit**

```bash
cd website && git add motion/compositions/loop-local/index.html public/media/loop-local-*
git commit -m "feat(motion): loop for what leaves the Mac"
```

---

### Task 6: Captures from the app in EZZK Demo mode

**Files:**
- Create: `website/motion/captures/zako-scan.png`, `zako-clause.png`, `zako-pin.png`, each with `<file>.json`

**Interfaces:**
- Produces: the three PNGs `render.mjs` stages for `loop-zako` and `product` (1440 x 900 window content, Retina 2x).

This task drives the installed Chevron7 through the granted computer-use access. It touches the owner's real app, so follow every safety step.

- [ ] **Step 1: Record the state to restore**

Run: `defaults read app.slovensko.chevron7 | grep -i -E "ezzkMode|activeProfileID"` and note both values. Note the register's row count: `python3 -c "import json;print(len(json.load(open('$HOME/Library/Application Support/Chevron7/Evidence/register.json'))['records']))"` (adjust the key if the file is a list).

- [ ] **Step 2: Switch to the sample setup in the app**

In Chevron7 Settings: EZZK → **Demo (lokálne)**. Profily advokáta → **Nový profil**: `JUDr. Ján Vzorový`, funkcia `advokát`, SAK `1234`, IČO `12345678`, názov kancelárie `Advokátska kancelária Vzorový` (all invented); make it active. Set the main window to 1440 x 900.

- [ ] **Step 3: Capture the scan and the clause**

Open `.impeccable/zako/Ukazkova_listina.pdf` (app repository) in Zaručená konverzia. After the analysis, confirm the suggested elements, then capture the window: `screencapture -o -x -l <window id> website/motion/captures/zako-scan.png` (window id from the computer-use window list). Continue to step 3 (clause) and capture `zako-clause.png`. If `screencapture` is refused for screen-recording permission, ask the owner to take the two captures with ⌘⇧4 then Space on the window.

- [ ] **Step 4: Capture the PIN prompt and cancel**

Click **Pokračovať na autorizáciu**, then **Autorizovať konverziu** with the SAK card inserted. When the PIN sheet appears, capture `zako-pin.png`, then click **Zrušiť**. Do not type a PIN. Nothing is signed and no number is allocated (allocation happens only after the PIN).

- [ ] **Step 5: Restore and verify**

In Settings: activate the owner's profile again and delete `JUDr. Ján Vzorový`; EZZK → **Produkcia**. Re-run Step 1's commands: `ezzkMode` and `activeProfileID` equal the noted values and the register row count is unchanged.

- [ ] **Step 6: Sidecars and commit**

For each PNG write `<name>.png.json`:

```json
{ "prompt": "Real capture, not generated: Chevron7 0.13.0, EZZK Demo mode, synthetic sample document Ukazkova_listina.pdf and an invented advocate profile; <screen>", "createdAt": "<ISO time of the capture>" }
```

with `<screen>` = `ZaKo review with confirmed elements`, `ZaKo clause step with live preview`, `authorization PIN prompt, cancelled`. Read each PNG and confirm no real name, number or document appears.

```bash
cd website && git add motion/captures
git commit -m "chore(motion): Chevron7 captures in EZZK Demo mode with a sample document"
```

---

### Task 7: Loop "Zaručená konverzia" (`loop-zako`)

**Files:**
- Create: `website/motion/compositions/loop-zako/index.html`
- Output: `website/public/media/loop-zako-{sk,en}.*`

**Interfaces:**
- Consumes: `assets/zako-scan.png`, `assets/zako-clause.png`, `assets/zako-pin.png` (Task 6); variables `scan`, `review`, `clause`, `mqc`, `number`, `cezzk`.

- [ ] **Step 1: Write the composition**

12 s. A capture panel on the left (crossfading scan, clause, PIN) with a slow push-in; a six-step list on the right whose current step is white and the rest Dusk Grey; the last two steps (number, CEZZK) are a drawn chain, not a capture. Locked state (list complete, chain drawn, "CEZZK" amber, clause capture shown) at 0 s and from 10.6 s.

```html
<!doctype html>
<html lang="sk" data-composition-variables='[
  {"id":"scan","type":"string","label":"Scan","default":"Sken listiny"},
  {"id":"review","type":"string","label":"Review","default":"Kontrola prvkov"},
  {"id":"clause","type":"string","label":"Clause","default":"Doložka"},
  {"id":"mqc","type":"string","label":"MQC","default":"Mandátny certifikát"},
  {"id":"number","type":"string","label":"Number","default":"Evidenčné číslo z EZZK"},
  {"id":"cezzk","type":"string","label":"CEZZK","default":"CEZZK: spracovaný"}
]'>
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=1280, height=720" />
  <link rel="stylesheet" href="assets/frame.css" />
  <script src="assets/gsap.min.js"></script>
  <style>
    .panel { position: absolute; left: 60px; top: 90px; width: 700px; height: 540px; border-radius: 16px; overflow: hidden; border: 1px solid var(--line-strong); }
    .panel img { position: absolute; inset: 0; width: 100%; height: 100%; object-fit: cover; object-position: left top; }
    .steps { position: absolute; left: 820px; top: 130px; margin: 0; padding: 0; list-style: none; display: grid; gap: 30px; }
    .steps li { display: grid; grid-template-columns: 36px 1fr; align-items: center; gap: 16px; color: var(--text-3); }
    .steps b { width: 14px; height: 14px; border-radius: 50%; border: 3px solid var(--line-strong); justify-self: center; }
    .chain { position: absolute; left: 836px; top: 470px; width: 20px; height: 120px; }
  </style>
</head>
<body>
  <div id="root" data-composition-id="loop-zako" data-start="0" data-width="1280" data-height="720" data-duration="12">
    <section class="clip" data-start="0" data-duration="12" style="position:absolute;inset:0">
      <div class="panel">
        <img id="i-scan" src="assets/zako-scan.png" alt="" />
        <img id="i-clause" src="assets/zako-clause.png" alt="" />
        <img id="i-pin" src="assets/zako-pin.png" alt="" />
      </div>
      <ol class="steps">
        <li id="t1"><b></b><span class="label" data-var-text="scan">Sken listiny</span></li>
        <li id="t2"><b></b><span class="label" data-var-text="review">Kontrola prvkov</span></li>
        <li id="t3"><b></b><span class="label" data-var-text="clause">Doložka</span></li>
        <li id="t4"><b></b><span class="label" data-var-text="mqc">Mandátny certifikát</span></li>
        <li id="t5"><b></b><span class="label" data-var-text="number">Evidenčné číslo z EZZK</span></li>
        <li id="t6"><b></b><span class="label" data-var-text="cezzk">CEZZK: spracovaný</span></li>
      </ol>
    </section>
  </div>
  <script>
    const tl = gsap.timeline({ paused: true });
    const steps = ['#t1', '#t2', '#t3', '#t4', '#t5', '#t6'];
    const on = (sel, t) => tl.to(`${sel} .label`, { color: '#f5f5f7', duration: 0.3 }, t)
      .to(`${sel} b`, { backgroundColor: '#f5f5f7', borderColor: '#f5f5f7', duration: 0.3 }, t);
    // Locked frame: every step lit, the last one amber, the clause capture on top.
    tl.fromTo('#i-scan', { opacity: 0 }, { opacity: 0, duration: 0.01 }, 0)
      .fromTo('#i-pin', { opacity: 0 }, { opacity: 0, duration: 0.01 }, 0)
      .fromTo('#i-clause', { opacity: 1 }, { opacity: 1, duration: 0.01 }, 0)
      .fromTo(steps.map((s) => `${s} .label`), { color: '#f5f5f7' }, { color: '#8d97ab', duration: 0.4 }, 0.2)
      .fromTo(steps.map((s) => `${s} b`), { backgroundColor: '#f5f5f7', borderColor: '#f5f5f7' },
        { backgroundColor: 'rgba(0,0,0,0)', borderColor: 'rgb(214 219 229 / 0.32)', duration: 0.4 }, 0.2)
      .fromTo('#t6 .label', { color: '#ffb23e' }, { color: '#8d97ab', duration: 0.4 }, 0.2)
      // 0.8 s scan, 2.4 s review, 4.0 s clause, 5.6 s PIN (MQC): the capture follows the step.
      .to('#i-clause', { opacity: 0, duration: 0.4 }, 0.6)
      .to('#i-scan', { opacity: 1, duration: 0.4 }, 0.6)
      .fromTo('#i-scan', { scale: 1 }, { scale: 1.06, duration: 3.2, ease: 'none', transformOrigin: '30% 40%' }, 0.8);
    on('#t1', 0.8); on('#t2', 2.4);
    tl.to('#i-scan', { opacity: 0, duration: 0.4 }, 3.8).to('#i-clause', { opacity: 1, duration: 0.4 }, 3.8);
    on('#t3', 4.0);
    tl.to('#i-clause', { opacity: 0, duration: 0.4 }, 5.4).to('#i-pin', { opacity: 1, duration: 0.4 }, 5.4);
    on('#t4', 5.6);
    // 7.4 s and 8.8 s: the number and the record in CEZZK (text and dots, no capture).
    on('#t5', 7.4); on('#t6', 8.8);
    tl.to('#t6 .label', { color: '#ffb23e', duration: 0.4 }, 9.4)
      .to('#t6 b', { backgroundColor: '#ffb23e', borderColor: '#ffb23e', duration: 0.4 }, 9.4)
      .to('#i-pin', { opacity: 0, duration: 0.4 }, 10.2).to('#i-clause', { opacity: 1, duration: 0.4 }, 10.2);
    window.__timelines['loop-zako'] = tl;
  </script>
</body>
</html>
```

- [ ] **Step 2: Check, snapshot at `0,1.5,4.5,6.5,9.8,11.9`, render, verify** as Task 2 Steps 2 and 3 with `loop-zako`. Expected: 0 s and 11.9 s identical (clause capture, all steps lit, last step amber); the PIN capture shows no PIN digits and no real name.

- [ ] **Step 3: Commit**

```bash
cd website && git add motion/compositions/loop-zako/index.html public/media/loop-zako-*
git commit -m "feat(motion): loop for the guaranteed conversion from scan to CEZZK"
```

---

### Task 8: Product video (`product`)

**Files:**
- Create: `website/motion/compositions/product/index.html`
- Output: `website/public/media/product-{sk,en}.*`

**Interfaces:**
- Consumes: `assets/{panel,mobile,stamp,zako-review,hero-icon}.mp4` (existing site recordings), the three captures, variables `l1` to `l6` and `url`.

- [ ] **Step 1: Write the composition**

50 s, 1920 x 1080, six scenes as in the spec table. Each recording is its own timed `<video>` (never inside a timed wrapper); the line sits below it in a non-timed caption band animated on the main timeline.

```html
<!doctype html>
<html lang="sk" data-composition-variables='[
  {"id":"l1","type":"string","label":"Line 1","default":"Kvalifikovaný podpis. Natívne na Macu."},
  {"id":"l2","type":"string","label":"Line 2","default":"Podpíšte PDF kartou eID, I.CA alebo preukazom SAK."},
  {"id":"l3","type":"string","label":"Line 3","default":"Bez čítačky: iPhone prečíta občiansky preukaz cez NFC."},
  {"id":"l4","type":"string","label":"Line 4","default":"Podpisujte priamo na slovensko.sk."},
  {"id":"l5","type":"string","label":"Line 5","default":"Zaručená konverzia: od skenu po záznam v CEZZK."},
  {"id":"l6","type":"string","label":"Line 6","default":"Dokumenty ostávajú na vašom Macu. Zadarmo, open source."},
  {"id":"url","type":"string","label":"URL","default":"chevron7.slovensko.app"}
]'>
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=1920, height=1080" />
  <link rel="stylesheet" href="assets/frame.css" />
  <script src="assets/gsap.min.js"></script>
  <style>
    .stage { position: absolute; left: 240px; top: 90px; width: 1440px; height: 810px; border-radius: 20px; object-fit: contain; }
    .still { position: absolute; left: 240px; top: 90px; width: 1440px; height: 810px; border-radius: 20px; object-fit: contain; opacity: 0; }
    .line { position: absolute; left: 0; right: 0; top: 940px; text-align: center; font-size: 46px; font-weight: 700; letter-spacing: -0.02em; opacity: 0; }
    .title { position: absolute; left: 0; right: 0; top: 760px; text-align: center; font-size: 76px; font-weight: 700; letter-spacing: -0.03em; opacity: 0; }
    .url { position: absolute; left: 0; right: 0; top: 880px; text-align: center; font-size: 40px; color: var(--amber); opacity: 0; }
    .icon { position: absolute; left: 660px; top: 120px; width: 600px; height: 600px; object-fit: contain; }
  </style>
</head>
<body>
  <div id="root" data-composition-id="product" data-start="0" data-width="1920" data-height="1080" data-duration="50">
    <video id="v-icon" class="icon clip" src="assets/hero-icon.mp4" data-start="0" data-duration="5" muted playsinline></video>
    <video id="v-panel" class="stage clip" src="assets/panel.mp4" data-start="5" data-duration="10" muted playsinline></video>
    <video id="v-mobile" class="stage clip" src="assets/mobile.mp4" data-start="15" data-duration="7" muted playsinline></video>
    <video id="v-stamp" class="stage clip" src="assets/stamp.mp4" data-start="22" data-duration="6" muted playsinline></video>
    <video id="v-zako" class="stage clip" src="assets/zako-review.mp4" data-start="28" data-duration="6" muted playsinline></video>
    <video id="v-icon2" class="icon clip" src="assets/hero-icon.mp4" data-start="44" data-duration="6" muted playsinline></video>
    <img id="s-clause" class="still" src="assets/zako-clause.png" alt="" />
    <img id="s-pin" class="still" src="assets/zako-pin.png" alt="" />
    <div id="t1" class="title" data-var-text="l1">Kvalifikovaný podpis. Natívne na Macu.</div>
    <div id="t2" class="line" data-var-text="l2">Podpíšte PDF kartou eID, I.CA alebo preukazom SAK.</div>
    <div id="t3" class="line" data-var-text="l3">Bez čítačky: iPhone prečíta občiansky preukaz cez NFC.</div>
    <div id="t4" class="line" data-var-text="l4">Podpisujte priamo na slovensko.sk.</div>
    <div id="t5" class="line" data-var-text="l5">Zaručená konverzia: od skenu po záznam v CEZZK.</div>
    <div id="t6" class="title" data-var-text="l6">Dokumenty ostávajú na vašom Macu. Zadarmo, open source.</div>
    <div id="t7" class="url" data-var-text="url">chevron7.slovensko.app</div>
  </div>
  <script>
    const tl = gsap.timeline({ paused: true });
    const show = (sel, from, to) => tl.fromTo(sel, { opacity: 0, y: 16 }, { opacity: 1, y: 0, duration: 0.6, ease: 'power3.out' }, from)
      .to(sel, { opacity: 0, duration: 0.4 }, to - 0.4);
    show('#t1', 1.2, 5); show('#t2', 5.4, 15); show('#t3', 15.4, 22); show('#t4', 22.4, 28); show('#t5', 28.4, 44);
    // 34 to 44 s: the clause and the PIN prompt after the review recording.
    tl.to('#s-clause', { opacity: 1, duration: 0.5 }, 34).to('#s-clause', { opacity: 0, duration: 0.5 }, 38.5)
      .to('#s-pin', { opacity: 1, duration: 0.5 }, 38.5).to('#s-pin', { opacity: 0, duration: 0.5 }, 43.5)
      // 44 to 50 s: the closing line and the address; held to the last frame (the poster).
      .fromTo('#t6', { opacity: 0, y: 16 }, { opacity: 1, y: 0, duration: 0.6, ease: 'power3.out' }, 45)
      .fromTo('#t7', { opacity: 0 }, { opacity: 1, duration: 0.6 }, 46);
    window.__timelines['product'] = tl;
  </script>
</body>
</html>
```

- [ ] **Step 2: Check and snapshot**

Run in `compositions/product`: `HYPERFRAMES_NO_TELEMETRY=1 npx hyperframes check`, then `npx hyperframes snapshot --at 2.5,10,18,25,31,36,41,48`.
Expected: 0 findings; every snapshot with a recording shows footage (a black or grey panel is render-blocking); lines fit on one row in both languages (render an English snapshot with `--variables-file .render/product-en.json` if `snapshot` accepts it, else check the English render's frames in Step 3).

- [ ] **Step 3: Render and verify**

Run: `cd website/motion && npm run render -- product`
Expected: `product-sk` and `product-en` each under 6144 kB at `1920,1080,30/1`, duration 50 s (`ffprobe -v error -show_entries format=duration -of csv=p=0 public/media/product-sk.mp4` prints 50.0). Extract and read frames at 10, 25, 36, 48 s of the English render with `ffmpeg -ss <t> -i ../public/media/product-en.mp4 -frames:v 1 /tmp/p-<t>.jpg`.

- [ ] **Step 4: Commit**

```bash
cd website && git add motion/compositions/product/index.html public/media/product-*
git commit -m "feat(motion): 50-second product video in Slovak and English"
```

---

### Task 9: `MotionLoop.astro` and the loops on the page

**Files:**
- Create: `website/src/components/MotionLoop.astro`
- Modify: `website/src/components/Home.astro` (pass `lang`)
- Modify: `website/src/components/Ways.astro`, `Local.astro`, `Zako.astro`

**Interfaces:**
- Consumes: `public/media/<name>-<lang>.mp4` and `-poster.jpg` (Tasks 2 to 7).
- Produces: `<MotionLoop name="loop-zako" lang="sk" />`.

- [ ] **Step 1: Write the component**

```astro
---
// A muted loop that plays only on screen and only under .motion; otherwise its poster
// (the loop's locked final frame) is all there is. Decorative: the text beside it
// carries the content.
interface Props {
  name: string;
  lang: string;
  class?: string;
}
const { name, lang, class: cls } = Astro.props;
const base = `/media/${name}-${lang}`;
---

<div class:list={['motion-loop', cls]} aria-hidden="true">
  <video muted playsinline loop preload="none" poster={`${base}-poster.jpg`} data-loop-src={`${base}.mp4`}></video>
</div>

<script>
  const loops = document.querySelectorAll<HTMLVideoElement>('video[data-loop-src]');
  if (document.documentElement.classList.contains('motion') && loops.length) {
    const seen = new IntersectionObserver((entries) => {
      for (const { target, isIntersecting } of entries) {
        const video = target as HTMLVideoElement;
        if (isIntersecting) {
          if (!video.src) video.src = video.dataset.loopSrc!;
          video.play().catch(() => {});
        } else {
          video.pause();
        }
      }
    }, { threshold: 0.4 });
    loops.forEach((v) => seen.observe(v));
  }
</script>

<style>
  .motion-loop {
    aspect-ratio: 16 / 9;
    border-radius: 14px;
    overflow: hidden;
    border: 1px solid var(--line);
    background: #0a0b1a;
  }
  video {
    display: block;
    width: 100%;
    height: 100%;
    object-fit: cover;
  }
</style>
```

- [ ] **Step 2: Pass the language down**

In `Home.astro` pass `lang={t.lang}` to `<Ways>`, `<Local>` and `<Zako>`, and add `lang: string` to each component's `Props` (`const { t, lang } = Astro.props;` in Ways; `const { t, lang } = Astro.props;` in Local; `const { t, media, lang } = Astro.props;` in Zako).

- [ ] **Step 3: Place the loops**

- `Ways.astro`: import `MotionLoop` and put `<MotionLoop name={['loop-way-card', 'loop-way-mobile', 'loop-way-safari'][n]} lang={lang} class="way-loop" />` as the first child of each `<li>`, with `.way-loop { margin-bottom: 1.4cqw; }` in its style block.
- `Local.astro`: `<MotionLoop name="loop-local" lang={lang} class="local-loop" />` after the `.relay` block, with `.local-loop { margin-top: 40px; max-width: 640px; }`.
- `Zako.astro`: `<MotionLoop name="loop-zako" lang={lang} class="zako-loop" />` right after `</ol>` of `.stages`, with `.zako-loop { margin: 48px auto 0; max-width: 1040px; }`.

- [ ] **Step 4: Build and verify the markup**

Run: `cd website && npx astro build && grep -c 'data-loop-src="/media/loop-' dist/index.html dist/en/index.html`
Expected: `5` for each file; `grep -o 'loop-zako-en.mp4' dist/en/index.html` prints one match and `dist/index.html` has none.

- [ ] **Step 5: Commit**

```bash
cd website && git add src/components/MotionLoop.astro src/components/Home.astro src/components/Ways.astro src/components/Local.astro src/components/Zako.astro
git commit -m "feat: HyperFrames loops in the ways, privacy and guaranteed conversion sections"
```

---

### Task 10: The video button and dialog in the hero

**Files:**
- Modify: `website/src/i18n/types.ts`, `sk.ts`, `en.ts` (hero `watch`, `watchTitle`, `close`)
- Modify: `website/src/components/Hero.astro`, `Home.astro` (pass `lang`)

**Interfaces:**
- Consumes: `public/media/product-<lang>.mp4` and poster (Task 8).

- [ ] **Step 1: Copy**

In `types.ts` extend the hero type with `watch: string; watchTitle: string; close: string;`. In `sk.ts` hero: `watch: 'Pozrieť video (50 s)', watchTitle: 'Chevron7 za 50 sekúnd', close: 'Zavrieť',`. In `en.ts` hero: `watch: 'Watch the video (50 s)', watchTitle: 'Chevron7 in 50 seconds', close: 'Close',`.

- [ ] **Step 2: Button and dialog**

In `Hero.astro` add `lang: string` to `Props`, then inside `.ctas` after the GitHub link:

```astro
<button class="cta cta-video" type="button" data-video-open>{t.watch}</button>
```

and before `</section>`:

```astro
<dialog class="video-dialog" aria-label={t.watchTitle} data-video-dialog>
  <video controls playsinline preload="none" poster={`/media/product-${lang}-poster.jpg`} data-video-src={`/media/product-${lang}.mp4`}></video>
  <button class="video-close" type="button" aria-label={t.close} data-video-close>×</button>
</dialog>
```

Script (append to the hero's existing `<script>`):

```ts
const dialog = document.querySelector<HTMLDialogElement>('[data-video-dialog]');
const opener = document.querySelector<HTMLButtonElement>('[data-video-open]');
if (dialog && opener) {
  const video = dialog.querySelector('video')!;
  opener.addEventListener('click', () => {
    // The file is fetched only now, never with the page.
    if (!video.src) video.src = video.dataset.videoSrc!;
    dialog.showModal();
    video.play().catch(() => {});
  });
  const close = () => dialog.close();
  dialog.querySelector('[data-video-close]')!.addEventListener('click', close);
  dialog.addEventListener('click', (e) => { if (e.target === dialog) close(); });
  dialog.addEventListener('close', () => { video.pause(); opener.focus(); });
}
```

Styles: `.video-dialog { padding: 0; border: 1px solid var(--line-strong); border-radius: 18px; background: #0a0b1a; width: min(1100px, 92vw); } .video-dialog::backdrop { background: rgb(10 11 26 / 0.82); } .video-dialog video { display: block; width: 100%; } .video-close { position: absolute; top: 10px; right: 12px; width: 40px; height: 40px; border-radius: 999px; border: 1px solid var(--line-strong); background: rgb(10 11 26 / 0.7); color: #f5f5f7; font-size: 24px; }`; give `.cta-video` the existing secondary CTA look (copy the rules of `.cta-github`).

- [ ] **Step 3: Build and verify**

Run: `cd website && npx astro build && grep -c 'data-video-src="/media/product-sk.mp4"' dist/index.html && grep -c 'data-video-src="/media/product-en.mp4"' dist/en/index.html`
Expected: `1` and `1`; `grep -c ' src="/media/product-' dist/index.html` (leading space, so `data-video-src` does not count) prints `0` (the video is not fetched with the page).

- [ ] **Step 4: Commit**

```bash
cd website && git add src/i18n src/components/Hero.astro src/components/Home.astro
git commit -m "feat: watch the 50-second product video from the hero"
```

---

### Task 11: Owner review and deploy

**Files:**
- Modify: `Chevron7/docs/superpowers/specs/2026-09-24-website-motion-design.md` (status line)

- [ ] **Step 1: Budgets and build**

Run: `cd website/motion && npm test && cd .. && npx astro build && ls -l public/media/loop-*-??.mp4 public/media/product-??.mp4`
Expected: tests pass, build completes, every loop under 614400 bytes, each product video under 6291456 bytes.

- [ ] **Step 2: Local preview for the owner**

Run: `cd website && npx astro preview --port 4321` in the background and give the owner `http://localhost:4321` and `http://localhost:4321/en/`. Ask them to check the five loops, the video button, and the page with reduced motion on (System Settings, Accessibility, Display, Reduce motion): posters only, no playback.

- [ ] **Step 3: Deploy after approval**

Only after the owner says yes: `cd website && git push origin main` (the site deploys). Watch `gh run list -R originalmagneto/chevron7-website -L 1` until `success`, then `curl -sI https://chevron7.slovensko.app/media/loop-zako-sk.mp4 | head -1` prints `HTTP/2 200`.

- [ ] **Step 4: Mark the spec implemented and push the app repository docs**

Change the spec's status line to `Status: implemented 2026-09-24 (website <short sha>).`, commit `docs: website motion implemented`, and push the app repository `main` with the spec, this plan and that commit (docs only, no release).

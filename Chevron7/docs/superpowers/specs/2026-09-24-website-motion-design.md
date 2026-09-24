# Website motion with HyperFrames: design

Date: 2026-09-24. Status: approved in conversation, awaiting spec review.
Scope: the website (`originalmagneto/chevron7-website`, checked out in `website/`).
The app is not changed.

## Goal

Make chevron7.slovensko.app more dynamic with videos rendered by HyperFrames
(`heygen-com/hyperframes`, HTML to deterministic MP4): short loops for three
sections and one product video, in Slovak and English, without breaking the
site's rules:

- every claim stays true of the shipped app (`PRODUCT.md`);
- app visuals are real captures of Chevron7 with synthetic sample documents;
  where no true capture exists, a diagram or typography stands in, never
  invented UI;
- the final, locked state is the default; motion runs only under `.motion`
  and never under reduced motion (`DESIGN.md`).

## Decisions taken with the owner

| Question | Decision |
| --- | --- |
| What HyperFrames produces | Loops for sections and a product video |
| Loops | ZaKo (5 stages and EZZK), the three ways to sign, "Dokumenty ostávajú na vašom Macu" |
| Product video placement | A button in the hero opening a player in a dialog; downloaded only on open |
| Sound and language | No sound; on-screen text; a Slovak and an English render |
| New app visuals | Stills captured by Claude from the app in EZZK Demo mode |
| Approach | Pre-rendered videos (approach A), not live compositions in the page |

## Architecture

New folder `website/motion/` with its own `package.json`, so HyperFrames never
enters the site build:

- `design.md`: the frame translation of `DESIGN.md`: Midnight ground `#0a0b1a`,
  one amber light (`#ffb23e`, `#ffd27a`), the text greys, the system font stack
  with Atkinson Hyperlegible Next as fallback, motion that lands on the final
  state.
- `copy/sk.json`, `copy/en.json`: every on-screen line. The Slovak lines are the
  site's own copy (`src/i18n/sk.ts`) or short derivations of it; the English
  lines mirror them.
- `compositions/`: one HTML composition per piece (`loop-zako`,
  `loop-way-card`, `loop-way-mobile`, `loop-way-safari`, `loop-local`,
  `product`), each reading its copy by language through a HyperFrames variable.
- `captures/`: new stills from the app, each with a `.json` sidecar (screen,
  app version, date, sample document, EZZK mode).
- `render.mjs` (`npm run render` in `motion/`): lints, checks and renders every
  composition in both languages, then writes to `website/public/media/`:
  `<name>-<lang>.mp4` (H.264, muted, `+faststart`), `<name>-<lang>-poster.jpg`
  (the final frame) and `<name>-<lang>.mp4.json` (sources, HyperFrames version,
  render date), matching the existing sidecar convention. Sidecars stay
  unpublished (`public/.assetsignore`).

Compositions and renders are committed. The Cloudflare deploy stays as it is;
nothing renders in CI.

### Formats and budgets

| Piece | Size | Rate | Length | Budget per language |
| --- | --- | --- | --- | --- |
| Loops | 1280 x 720 | 24 fps | 6 to 12 s, seamless | about 600 kB |
| Product video | 1920 x 1080 | 30 fps | about 50 s | about 6 MB |

## Content

### Loop "Zaručená konverzia" (about 12 s, beside the five stages)

1. Scan: a real capture of a sample document; the found security elements
   light up one frame after another.
2. Clause: a capture of the live clause preview; the eight fields arrive in
   order.
3. Authorization: a capture of the PIN prompt and the "Mandátny certifikát"
   label.
4. EZZK as a diagram: evidence number, signed record, CEZZK, "Spracovaný".
   Demo mode never reaches "Spracovaný", so this part is not a capture.

### Loops "Spôsoby podpisu" (about 6 s each, one per card)

- Kartou: a card slides into a reader, PIN dots fill, an amber seal "podpísané".
- Mobilom: a QR code on the Mac, an iPhone, NFC waves, the document returns.
- V Safari: a portal window, the Chevron7 panel "Potvrdiť", signed.

Icons and lines in the site's style, no captures.

### Loop "Dokumenty ostávajú na vašom Macu" (about 10 s, beside the section text)

The document stays inside a Mac outline. Only a short fingerprint leaves for
the timestamp authority, and a question goes to the EU trusted lists. For
mobile signing the encrypted document passes the relay and a 24-hour track
drains. The section's existing relay animation stays.

### Product video (about 50 s)

| Time | Picture | Slovak line |
| --- | --- | --- |
| 0 to 5 s | The icon and the seven chevrons | Kvalifikovaný podpis. Natívne na Macu. |
| 5 to 15 s | The card signing recording | Podpíšte PDF kartou eID, I.CA alebo preukazom SAK. |
| 15 to 22 s | The mobile signing recording | Bez čítačky: iPhone prečíta občiansky preukaz cez NFC. |
| 22 to 28 s | The Safari signing panel | Podpisujte priamo na slovensko.sk. |
| 28 to 44 s | ZaKo review, clause, PIN, the EZZK diagram | Zaručená konverzia: od skenu po záznam v CEZZK. |
| 44 to 50 s | The icon and the address | Dokumenty ostávajú na vašom Macu. Zadarmo, open source. chevron7.slovensko.app |

Existing recordings are reused from `public/media/` (`panel`, `mobile`,
`stamp`, `zako-review`, `hero-icon`).

## Site integration

- Hero: a secondary button "Pozrieť video (50 s)" / "Watch the video (50 s)"
  beside the download button. It opens a native `<dialog>` (Esc and a click on
  the backdrop close it, focus returns to the button) holding a `<video
  controls>` whose `src` is set only on open. `/` gets the Slovak render,
  `/en/` the English one.
- `MotionLoop.astro`: one component for every loop: a muted, `playsinline`,
  `loop`, `preload="none"` video with its poster. It plays only while on
  screen (IntersectionObserver) and only under `.motion`; under reduced motion
  the poster is all there is. Loops are `aria-hidden`, since the text beside
  them carries the content.
- Placement: `Zako.astro` beside the stages list, each card of `Ways.astro`,
  and `Local.astro` beside the lead.

## Captures

Taken through the granted computer-use access, in a window of fixed size, with
a sample document of an invented company and an invented advocate in the
profile. For the session EZZK is switched to Demo and the advocate profile is
swapped; both are restored afterwards (Production and the owner's profile).
The authorization stops at the PIN prompt and is cancelled: nothing is signed
and no row is written to the owner's register, which is a legal record. No
real conversion, name or number appears.

## Verification

- `hyperframes lint` and `check` on every composition.
- Key frames of every render extracted and reviewed: text, cropping, colours,
  both languages.
- File sizes against the budgets; `astro build`.
- A local preview of the site for the owner before the push to `main`, which
  deploys immediately.

## Out of scope

The app itself, the website copy outside the new button label, sound, a live
HyperFrames runtime in the page, and rendering in CI.

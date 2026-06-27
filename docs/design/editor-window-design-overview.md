# VoodooTracker X — Editor Window Design Overview

**Scope:** First-pass window concepts for the Song / Order editor, Instrument editor, and Sample
editor. Design specification + static HTML mockups only.

**Status:** Design-only. Nothing here changes app behavior, runtime playback, the parser/audio
backend, editor/audition behavior, or the tracker viewport. These documents exist to guide future,
narrowly-scoped implementation PRs.

This overview ties together:

- `docs/design/editor-control-vocabulary.md` — the shared tactile control library (knobs, switches,
  sliders, segment readouts, LEDs) reused across all three windows.
- `docs/design/song-order-editor-window.md`
- `docs/design/instrument-editor-window.md`
- `docs/design/sample-editor-window.md`
- `assets/mockups/song-order-editor-v1.html`, `assets/mockups/instrument-editor-v1.html`,
  `assets/mockups/sample-editor-v1.html` — static, dependency-free visual references.
- `assets/mockups/editor-control-knob-lab.html` — canonical reference for the knob + pan slider.

It builds directly on `docs/design/UI-DESIGN-control-panel.md`; the editor windows reuse that
panel's palette, monospace type, and recessed-vs-interactive field hierarchy.

---

## 1. Product framing

- These are **three independent floating utility windows**, each opened from a menu item. The main
  tracker window stays open; several editor windows may be open at once on large monitors.
- **Fixed sizes** for the first pass (one size per window). Resizing can come later; the Sample
  editor is the most likely first candidate.
- VTX v1.0 is a **sample/instrument tracker first** — not a DAW. No arrangement timeline, no live
  plugin hosting (AUv3/VST), no automation lanes, no native project format in this pass.
- The design should stay **approachable and composition-first** — clear tracker semantics without
  Renoise-level density — and should translate to a future iPad/touch surface.

---

## 2. Chosen visual direction — "Hybrid VTX Workstation / Tactile Machine"

Keep the existing VTX **dark graphite + amber/gold flat palette**, and organize each window with the
**tactile density and grouping of a 1990s hardware groovebox**: clusters of knobs, small toggle
switches, segment-style readouts, and machine-like labelled sections. The reference that set the
direction is the iElectribe groovebox panel (knobs with a toothed value halo, little indicator
lamps), reinterpreted in VTX's dark palette rather than its red chassis or brushed-metal gloss.

The result reads as old-school hardware without the rendering cost or dated look of full
skeuomorphism, and without abandoning the established VTX identity.

### Three directions were explored (rejected alternatives)

1. **Classic Tracker Utility** — almost entirely fields/steppers/popups like the control panel, few
   or no knobs. *Rejected as the whole system:* fastest to ship and very legible, but least
   distinctive and weakest touch story. Its discipline is retained for the Song / Order editor spine.
2. **Groovebox / Tactile Machine (maximal)** — lean fully into knobs/switches/segment LEDs for every
   parameter. *Rejected as-is:* strongest identity but risks overwhelming a composition-first user,
   and pure knobs are imprecise for exact integers (loop points, relative note).
3. **Hybrid VTX Workstation — chosen.** Flat graphite + amber discipline organized with tactile
   density: knobs for continuous params, steppers for exact integers, segment readouts everywhere,
   small switches for enables/modes. Each window is a set of labelled hardware "sections."

---

## 3. Shared design decisions

- **Palette:** reuse the control-panel tokens — window `#1E1E1E`, panel `#252526`, recessed readout
  `#181819`, interactive `#1C1C1D`, accent gold `#C9A74A` (+ opacity ramp), warm value text
  `#E8D8A0`, play-green `#4DB868`.
- **Two limited expansion accents, used sparingly:** a cool **indigo selection** `rgba(70,84,125,…)`
  (already the tracker highlight hue) for selected list rows / order slots / waveform selection; and a
  small **indicator-LED red** `#E0473A` used only as tiny armed/active/centered lamps (kept distinct
  from the muted danger-red used on Stop / Clear).
- **Typography:** monospace throughout, matching the tracker identity.
- **Section model:** every window is a grid of labelled hardware panels; controls that configure a
  panel sit on the panel's header line (e.g. ENVELOPE shows VOL/PAN + add/del point on its header).
- **Control vocabulary:** documented once in `docs/design/editor-control-vocabulary.md` and reused by
  all three windows.

### Per-window summary

| Window | Fixed size | Density | Centerpiece |
|---|---|---|---|
| Song / Order | ~660 × 480 | switch/button heavy, no knobs | order list + paginated pattern bank |
| Instrument | ~920 × 638 | envelope + keymap canvases, knob clusters | volume envelope + note keymap |
| Sample | ~940 × 560 | waveform-dominant, one knob cluster | waveform line + destructive-edit bank |

---

## 4. Cross-cutting guardrails

- **Protect the playback path and tracker viewport.** These windows drive document and audition state
  only. No editor introduces a second playback path, changes mixer timing, or touches the
  static-highlight tracker rendering.
- **Audition reuses the existing isolated preview path** — never full-song playback.
- **Narrow PRs.** Build each window in slices: window shell → static panels/readouts → list/canvas
  views → wired controls → audition. The reusable controls (knob, switch, slider, segment, LED,
  canvas) land as their own pieces first and are shared across windows.
- **No DAW timeline, no plugin hosting, no automation lanes, no native project format** in this pass.

---

## 5. v1.0 scope

**In:** pattern editor (existing), song/order editor, instrument editor, sample editor foundations;
WAV/AIFF sample import; XI instrument import target; copying instruments/samples from existing
modules into editable songs; loop-and-edit workflow; save XM; export WAV/AAC. Sample editor includes
**waveform generators** (sine/square/triangle/saw/noise) and **destructive edits**
(trim/crop/cut/copy/paste/normalize/reverse/fade) with undo.

**Deferred:** AUv3/VST hosting; automation lanes; native VTX project format; AI-assisted content;
DAW-style arrangement timeline; external MIDI keyboard input (on-screen keyboard only, MIDI left as a
future hook); resizable editor windows; showing every XM envelope field at once (staged instead).

---

## 6. How to use these documents

For the *why* and the *what-not-to-build-yet*, read each window spec. For the *where things go*, open
the matching mockup in a browser (they are static and dependency-free). For any new control, follow
`docs/design/editor-control-vocabulary.md` so knobs, sliders, switches, and LEDs stay consistent.

# VoodooTracker X — Editor Control Vocabulary

The shared tactile control library used by all three editor windows (Song / Order, Instrument,
Sample). Defining it once keeps knobs, sliders, switches, LEDs, and readouts consistent across the
editors and any future UI work.

**Status:** Shared theme, panel label, segment readout, indicator LED, chunky button, knob, and
center-detent pan slider primitives now exist as additive AppKit foundations. The Song / Order editor
and read-only Instrument Editor shell consume this vocabulary; Instrument Editor canvases are inert
display views only. Switches and interactive canvas behavior remain design-only. Reference:
`assets/mockups/editor-control-knob-lab.html` is the canonical visual for the knob and pan slider;
the per-window mockups show them in context.

This vocabulary extends the control-panel system in `docs/design/UI-DESIGN-control-panel.md` — same
palette, same monospace, same recessed-vs-interactive hierarchy.

---

## 1. Palette tokens

| Role | Value |
|---|---|
| Window background | `#1E1E1E` |
| Panel surface | `#252526` |
| Recessed readout background | `#181819` |
| Interactive field background | `#1C1C1D` |
| Accent gold | `#C9A74A` (used at full + 60/55/38/22/12% opacity) |
| Warm value text | `#E8D8A0` |
| Play / active green | `#4DB868` |
| Selection (indigo) | `rgba(70,84,125, …)` — selected list rows / order slots / waveform region |
| Indicator LED red | `#E0473A` — tiny armed/active/centered lamps only |
| Danger red | `#CC5A50` — Stop / Clear buttons (kept visually distinct from the LED red) |

Two expansion accents only: the indigo selection and the red indicator LED. Everything else stays in
the graphite + amber family.

---

## 2. The knob

The signature control. A uniform dark **chamfered body** with a **toothed value arc** and a
**recessed, carved indicator**.

- **Body (uniform size everywhere).** Dark chamfered cap recessed into a shallow well: a soft top
  reflection, an inset bottom shadow, a domed center. Reads as a 1990s synth-panel pot in the VTX
  dark palette. Knob bodies are the **same size** across a window; importance is never shown by
  growing the body.
- **Toothed value arc.** A ring of short radial teeth around the body. Teeth are **lit gold up to the
  current value** and **dim past it** — the dim teeth read as the scale, the lit teeth as the value.
  This is the iElectribe "halo," reinterpreted in amber.
- **Importance via halo size.** A control that matters more (e.g. the default/sample VOLUME) gets a
  **bigger, brighter toothed halo** while keeping the same body. This is the only emphasis lever for
  knobs — never a larger knob.
- **Recessed indicator.** The pointer is a carved groove (dark, inset-shadowed) with a small lit gold
  tip, not a flat line painted on top.
- **Pairing.** Every knob is paired with a small numeric segment readout. Interaction intent:
  vertical click-drag to adjust, double-click to type an exact value — so a knob's imprecision is
  never a dead end.

**Rejected knob alternatives** (explored, not chosen): a flat modern arc-knob (read as too
contemporary), and two heavier 3D bodies — a faceted-metal collar and a knurled dome (good but
busier than the chamfered well). The chosen chamfered body + toothed arc is the standard.

---

## 3. The pan slider (with center detent)

Panning uses a **horizontal slider**, not a knob — easier to read center at a glance and a better fit
for touch.

- A center tick marks the detent. When the thumb is **parked at center**, the center tick glows and a
  small indicator LED lights — a clear "you're centered" cue.
- The detent is meant to *feel* like a notch you pull into and out of. On a future touch/iPad build,
  center is where a **haptic tap** should fire; on desktop, the value should lightly snap to center.
- Replaces an earlier large "CTR" text readout, which was visually heavy.

---

## 4. Other controls

| Control | Use | Notes |
|---|---|---|
| **Stepper field** | Exact integers (loop start/end, relative note, order position, restart, pattern number, envelope point index, fadeout) | Reuse the control-panel stepper. Precision matters — never a knob. |
| **Toggle switch** | Binary enables (envelope enable, sustain enable, loop enable) | Small pill switch, amber when on. |
| **Segmented switch** | 3–4 way modes (loop None/Fwd/Pingpong, envelope VOL/PAN, vibrato type) | Lit segment is gold. |
| **Segment readout** | Any value display | Recessed `#181819`, warm amber-white digits, faint glow — the "LED" of the panel. |
| **LED indicator lamp** | Armed / active / centered state next to a control | Small round glowing lamp; red `#E0473A` for armed/active, dark when off. Indicator only, never a button. |
| **Chunky button** | Actions (insert/delete/dup, trim/normalize, generate-waveform, new/dup/clear) | Flat dark with gold border; danger tint for destructive actions. Icon-above-label form for tool banks. |
| **Canvas view** | Envelope graphs, waveform display, note keymap | Custom-drawn views. Graphite background, amber strokes, indigo selection, gold/red markers. |

---

## 5. When to use what

- **Continuous, approximate** (volume, pan amount, vibrato depth/rate/sweep, fine tune, fade amount,
  fadeout) → **knob** (pan is the exception → **slider**).
- **Exact integer** (loop points, relative note, order/pattern indices, envelope point indices) →
  **stepper**.
- **Binary / small mode set** → **switch** or **segmented switch**.
- **Panel-level selectors and add/remove actions** → put them on the panel's **header line** to keep
  the body clean (e.g. ENVELOPE header carries VOL/PAN + add/del point; VIBRATO header carries the
  type selector; DEFAULTS header carries relative note).

---

## 6. AppKit implementation notes (for future PRs)

Keep these as their own narrow, reusable pieces, landed before the windows that consume them:

- A reusable **knob control** (custom `NSControl`) now draws the chamfered body, toothed value arc,
  recessed indicator, and an "emphasized" variant with the larger halo. It pairs with a segment
  readout; double-click numeric entry remains deferred.
- A reusable **pan slider** with a center detent now provides value snap + lit center + optional
  indicator state, structured so a touch build can attach haptics at center later.
- A reusable **indicator-LED view** (red/amber/off) — decorative state output only.
- **Segment readout**, **toggle/segmented switch**, and **stepper** components shared with the control
  panel.
- **Canvas views** (envelope editor, waveform display, note keymap) as custom `NSView`s using Core
  Graphics; downsample waveforms for display and avoid per-sample/per-point subviews.

Reuse the existing control-panel theme tokens; introduce no new colors beyond the indigo selection
and the red indicator LED. Do not change the audio backend, mixer, parser, or tracker viewport in
these PRs. Manual visual verification (before/after screenshots) per the project's visual-verification
practice.

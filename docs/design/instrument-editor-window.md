# VoodooTracker X — Instrument Editor Window

**Window:** Instrument editor (independent floating utility window).
**Implemented read-only shell size:** 920 × 638.
**Mockup:** `assets/mockups/instrument-editor-v1.html`.
**Reference:** FastTracker II instrument editor, reinterpreted in VTX's tactile language.
**Status:** The fixed-size shell now follows the v1 mockup hierarchy with read-only
document/selection binding. Editing, undo, import/export XI behavior, envelope/keymap editing,
waveform display, and audition changes remain future work. The shell does not change playback, the
tracker viewport, the parser, writers, exports, or audio backend.

See `docs/design/editor-window-design-overview.md` and `docs/design/editor-control-vocabulary.md`.

### Implemented read-only foundation

`Window > Instrument Editor` opens one reusable AppKit utility window using the mockup's header,
left instrument/sample lists, center envelope panel, right vibrato/defaults panels, and bottom note
keymap hierarchy. It follows the current loaded module, editable document, or editable copy plus the
main control-panel instrument and sample selection. The shell shows represented instrument
number/name/sample count, sample slot/name/length/loop mode and range/volume/relative note/finetune,
an immutable volume-envelope preview, and represented note-to-sample ranges. Missing data has an
explicit empty state. Future buttons, knobs, tabs, panning/vibrato fields, XI actions, keymap
assignment, and audition affordances are disabled/inert; a compact header badge states read-only.
No controls mutate data.

---

## 1. Purpose and mental model

An **instrument** is a named container that maps **notes → samples** and adds **envelopes**,
**vibrato**, and **default playback parameters** on top of its samples. Playing a note with an
instrument looks up which sample slot that note maps to, then plays it shaped by the instrument's
envelopes, fadeout, and vibrato.

Mental model, top to bottom: pick an instrument (it has a name + sample slots) → shape it (volume
envelope, panning envelope, fadeout, vibrato) → map it to the keyboard (sample per note range) → set
defaults (volume, pan, relative note, fine tune).

The guardrail throughout: **approachable, not Renoise-intimidating.** Essentials are forward and
large; advanced fields are present but grouped, not hidden.

---

## 2. Primary user workflows

1. **Name and build:** select an empty instrument → name it → assign samples into its slots → map
   them across the keyboard.
2. **Shape amplitude:** enable the volume envelope → add/drag points → set sustain and loop points →
   set fadeout; audition to hear it.
3. **Add movement:** set vibrato type and dial depth/rate/sweep; optionally enable the panning
   envelope (shares the graph via a VOL/PAN switch).
4. **Tune:** set relative note and fine tune so the sample sits at the right pitch; set default
   volume/pan.
5. **Audition while editing** via the isolated preview path (not full-song playback).

---

## 3. Visual layout

Header (instrument selector, name, XI import/export, audition), a center row of four panels, and a
full-width note keymap below.

```
┌─ Instrument ──────────────────────────────────────────────────────────────┐
│ INST [I01]  NAME [ Deep Bass        ]  [IMPORT XI][EXPORT XI]  AUDITION ◀C4▶▶│
│ ┌INSTRUMENTS┐ ┌ ENVELOPE  [VOL|PAN] [ADD PT][DEL PT]   ENABLE◉┐ ┌VIBRATO ∿⊓⊿◺┐│
│ │ list fills │ │   envelope graph (landscape canvas)          │ │ SWEEP DEPTH│ │
│ │            │ │                                              │ │  RATE      │ │
│ ├SAMPLE SLOTS┤ │ SUSTAIN◉ PT[05]  LOOP◉ ST[02] EN[04]   FADE[0080]│ ┌DEFAULTS REL┐│
│ │ list fills │ └──────────────────────────────────────────────┘ │ VOL  FINETUNE│ │
│ └────────────┘                                                   │ PAN ───●──── │ │
│ ┌ NOTE KEYMAP  ◀C-2  C-4▶ ───────────────────────────────────────────────────┐ │
│ │ color band: S00 | S01 | S02   [3-octave keyboard, click=audition, drag=assign]│ │
│ └───────────────────────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────────────────┘
```

Panel-level controls live on each header line (VOL/PAN + add/del point on ENVELOPE; type icons on
VIBRATO; relative note on DEFAULTS) to keep the bodies clean and the boxes uniform. The signature
DEFAULTS **VOLUME** knob carries the larger toothed halo.

---

## 4. Control groups

- **INSTRUMENT list / SAMPLE SLOTS list:** scrollable, fill their boxes; selection drives the editor.
- **NAME + XI import/export + AUDITION:** editable name; XI import/export affordances (see §7); an
  audition note nudge + play + armed LED, via the isolated preview path.
- **ENVELOPE (center):** VOL/PAN segmented switch + add/del point on the header; a landscape graph
  canvas (points, sustain marker, loop region); a control row with ENABLE, SUSTAIN + point, LOOP +
  start/end, and FADE (fadeout).
- **VIBRATO:** type selector on the header (sine/square/ramp icons + a lit LED), and SWEEP / DEPTH /
  RATE knobs.
- **DEFAULTS:** relative note on the header; VOLUME (signature, larger halo) + FINETUNE knobs and a
  center-detent PAN slider.
- **NOTE KEYMAP:** full-width keyboard (~3 octaves, with octave-shift buttons) and a color band
  showing the sample assigned to each note range; click to audition, drag to assign the selected
  sample to a range.

---

## 5. Required controls for v1.0

Instrument list + name; sample slot list + selected sample; note keymap with per-range assignment;
volume envelope + panning envelope (via VOL/PAN switch); envelope enable, sustain + point, loop +
start/end, add/delete point; fadeout; vibrato type/sweep/depth/rate; default volume/pan; relative
note; fine tune; audition controls. All present — "staged" means the volume envelope + keymap are the
forward centerpieces and the secondary fields are grouped, not hidden.

---

## 6. Nice-to-have controls for later

Envelope predefs (quick shapes); simultaneous VOL+PAN graphs on a larger/resizable window; auto-map
helper; envelope point numeric table / snap-to-grid; copy envelope between instruments; external MIDI
keyboard input (deferred hook).

---

## 7. What not to include yet

No external MIDI input wiring (on-screen keyboard only; leave the hook); no simultaneous dual-envelope
view in the fixed first pass (use the VOL/PAN switch); no modulation matrix/LFO beyond XM vibrato; no
inline sample editing (provide a jump to the Sample editor).

**Instrument files (XI):** the canonical import/export commands live in the app's Instrument menu.
The window shows IMPORT XI / EXPORT XI affordances for discoverability that call those same commands —
the window does not own separate file semantics.

---

## 8. Interaction notes

- Selecting an instrument repopulates name, sample slots, envelopes, vibrato, defaults, and keymap.
- The VOL/PAN switch swaps which envelope the canvas + envelope controls operate on.
- Knobs: vertical drag, double-click to type; every knob has an exact numeric segment. Pan uses the
  center-detent slider.
- Keymap: click = audition that note with the current instrument; drag across keys = assign the
  selected sample slot to that note range; the color band updates live.
- All audition goes through the isolated preview path — never full-song playback.

---

## 9. Keyboard / navigation notes

Up/Down move instrument selection; the computer keyboard plays audition notes in the classic tracker
layout when the keymap area has focus (octave follows the audition octave control); `V`/`P` toggle the
envelope between Volume and Panning; `A` add point, `Delete` remove; Tab cycles instrument list →
name → sample slots → envelope → vibrato → defaults → keymap.

---

## 10. AppKit implementation notes

- Fixed-size window, single shared instance, menu-toggled.
- **Lists:** view-based tables for instruments and sample slots; custom cell drawing; indigo
  selection; lists fill their panels.
- **Envelope canvas:** the current custom view draws represented volume points and sustain/loop
  context but returns no hit target. Future editing may add point hit-testing/drag without creating
  per-point subviews.
- **Knobs / pan slider / LEDs / switches / segments:** reuse the shared control library
  (`docs/design/editor-control-vocabulary.md`).
- **Keymap:** the current custom views draw the keyboard placeholder + represented per-range color
  band but return no hit target. Future click/drag behavior may add isolated-preview audition and
  assign-range handling.
- All edits mutate the selected instrument's document state through the existing document command
  layer. Do not alter the audio backend, mixer, parser, or tracker viewport.

### Suggested PR sequence

1. Done: v1-mockup window shell + menu command + read-only instrument/sample-slot,
   volume-envelope-preview, and note-map-range binding.
2. Add the document applyEdit/undo funnel required before mutation.
3. Add editable palette/sample foundations in narrow slices.
4. Complete any shared editing-control primitives still needed for mutation.
5. Envelope editing (points, sustain, loop, add/del) wired.
6. VOL/PAN switch + panning envelope.
7. Vibrato + defaults clusters wired.
8. Note-keymap audition through the isolated preview path.
9. Keymap drag-to-assign-range.

---

## 11. Testing / manual verification

For the implemented shell, verify empty/default, loaded-module, editable-copy, and selection-change
states; confirm one window is reused; and confirm every field remains read-only. Use public-safe
fixtures only and keep screenshots local/untracked.

For later interactive slices, screenshot before/after per PR and verify the surface reads as calm at
fixed size. Envelope: points
add/drag/delete; sustain/loop markers track point indices; VOL/PAN swaps cleanly; fadeout maps
correctly. Knobs ↔ segments stay in sync; double-click entry clamps to valid ranges; relative note +
fine tune affect audition pitch. Keymap: color band matches assignments; drag-assign updates the right
range; clicking auditions via the preview path (assert no full-song path is triggered). No change to
mixer timing, audio backend, or tracker viewport while open.

---

## 12. Risks and open questions

- Envelope point editing is the highest-complexity custom view — land it read-only first, then add
  editing, to stay narrow.
- Too many knobs could tip into "intimidating" — grouping + the single signature knob are the
  mitigations; verify with a fresh user.
- Keymap drag-assign can be fiddly — use a small drag threshold so click-audition and drag-assign do
  not conflict.
- Open: secondary cluster vs. explicit "advanced" disclosure for vibrato/relative note.
- Open: drag-to-assign-range vs. per-key assignment first.
- Open: envelope predefs in v1.0 or later (assumed later).

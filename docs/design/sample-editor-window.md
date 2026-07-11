# VoodooTracker X — Sample Editor Window

**Window:** Sample editor (independent floating utility window).
**Fixed size (first pass):** ~940 × 560. (Most likely first candidate for a later resizable pass.)
**Mockup:** `assets/mockups/sample-editor-v1.html`.
**Reference:** FastTracker II sample editor, reinterpreted in VTX's tactile language.
**Status:** Design-only. The shared document applyEdit/whole-snapshot undo foundation now exists,
but no Sample Editor, waveform editing, sample import/export, or sample mutation has been added.
This design does not change playback, audition, the tracker viewport, the parser, or audio backend.

See `docs/design/editor-window-design-overview.md` and `docs/design/editor-control-vocabulary.md`.

---

## 1. Purpose and mental model

The Sample editor is **direct waveform editing** of a single sample: see the waveform, select a
region, set loop points, and apply edits (trim, crop, normalize, reverse, fade) or generate a basic
waveform from scratch. It is the most "hardware bench" of the three windows — a big display with
controls underneath.

Mental model: **the waveform is the document.** Everything else (loop cluster, sample params, edit
bank, generators, file) acts on the waveform or the current selection.

v1.0 deliberately includes **destructive editing** (with undo) and **waveform generators**.

---

## 2. Primary user workflows

1. **Audition + set loop:** select a sample → play → drag loop start/end flags on the waveform → pick
   loop mode (None / Forward / Pingpong) → audition again.
2. **Trim/crop:** drag a selection → Crop (keep selection) or Trim (drop silent ends).
3. **Clean up:** Normalize; Fade In/Out; Reverse; Cut/Copy/Paste between regions or samples.
4. **Generate from scratch:** clear → Generate sine/square/triangle/saw/noise → shape → set a loop.
5. **Tune for the keymap:** set relative note + fine tune; set sample volume/pan.

---

## 3. Visual layout

Header (sample selector, name, format, audition), a dominant waveform panel with zoom/scroll inside
it, a row of three panels (loop / sample params / generate+file), and a full-width edit bank.

```
┌─ Sample ───────────────────────────────────────────────────────────────────┐
│ SMP [S00]  NAME [ Bass C2 ]  FORMAT 16-bit·44100·mono   AUDITION ◀C-4▶ ▶ ◉   │
│ ┌SAMPLES┐ ┌ WAVEFORM (single line, indigo selection, red loop flags) ───────┐│
│ │ list   │ │   ╱╲╱╲╱╲╱╲╱╲╱╲                                                 ││
│ │ fills  │ │  LEN  SEL   ZOOM ▭──  SCROLL ───▭───   (inside the panel)       ││
│ └────────┘ └───────────────────────────────────────────────────────────────┘│
│ ┌ LOOP ───────────┐ ┌ SAMPLE PARAMS ──┐ ┌ GENERATE  ∿ ⊓ ⊿ ◺ ▦ ───────────────┐│
│ │ MODE [N|F|P] ◉   │ │ VOL   FINETUNE   │ │ ┌ FILE  LOAD EXPORT CLEAR REPLACE ┐ ││
│ │ START END LENGTH │ │ PAN ───●───      │ │ │ (icon-above-label, fills column)│ ││
│ │ LOOP REGION view │ │ REL [C-4]        │ │ └─────────────────────────────────┘ ││
│ └──────────────────┘ └──────────────────┘ └─────────────────────────────────────┘│
│ ┌ EDIT  TRIM CROP | CUT COPY PASTE | NORMALIZE REVERSE FADE IN FADE OUT | UNDO ┐│
│ └───────────────────────────────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────────────────────────────────┘
```

The waveform is a single amber line on graphite, with an indigo selection region and red loop-point
flags. The signature SAMPLE PARAMS **VOLUME** knob carries the larger toothed halo.

---

## 4. Control groups

- **SAMPLE list:** scrollable sample slots; fills its box; selection drives the editor.
- **NAME / FORMAT / AUDITION:** editable name; read-only format (bit depth · rate · channels);
  audition (note nudge, play, armed LED) via the isolated preview path.
- **WAVEFORM canvas (dominant):** single-line waveform; draggable selection (indigo); draggable loop
  start/end flags (red); length + selection readouts; zoom + scroll controls **inside** the panel.
- **LOOP:** mode (None / Forward / Pingpong) + armed LED; start / end steppers; derived length
  readout; a small loop-region preview.
- **SAMPLE PARAMS:** VOLUME (signature) + FINETUNE knobs; center-detent PAN slider; relative note.
- **GENERATE:** sine / square / triangle / saw / noise (each replaces the sample; confirm-on-replace).
- **FILE:** sample LOAD (WAV/AIFF) / EXPORT / CLEAR / REPLACE — prominent, since sample editing is
  file/media-oriented. (Instrument XI files are menu-canonical; see the instrument window spec.)
- **EDIT bank (full width):** Trim, Crop · Cut, Copy, Paste · Normalize, Reverse, Fade In, Fade Out ·
  Undo.

---

## 5. Required controls for v1.0

Sample list + selected sample; waveform display; zoom + scroll; play/stop audition + audition note;
loop mode None/Forward/Pingpong; loop start; loop end + derived length; sample length display; sample
volume/pan; relative note; fine tune; bit depth/format display; trim; crop; cut/copy/paste; normalize;
fade in/out; reverse; generate sine/square/triangle/saw/noise; clear sample; sample load/save in this
window.

---

## 6. Nice-to-have controls for later

Visible edit history; spectrum or RMS/peak overlay; resample / pitch-shift / format convert; filters
(lp/hp) and X-fade loop smoothing; snap selection to zero-crossings; auto loop-point finder;
drag-and-drop import.

---

## 7. What not to include yet

No filter/resonance/X-fade effects page in v1.0 (basic destructive set first); no spectral editing,
time-stretch, or real-time DSP preview; no multi-sample batch ops; no second playback path (audition
reuses the isolated preview surface).

---

## 8. Interaction notes

- Click-drag on the waveform creates a selection; most edits act on the selection, or on the whole
  sample if none. Loop flags drag separately from the selection (give them their own handles).
- Loop start/end are exact steppers **and** draggable flags; length is derived (end − start).
- Destructive ops push a single undo step (v1.0); generators and Clear confirm before replacing;
  Normalize peaks at full scale without clipping; Reverse/Fade act on the selection.
- Knobs: vertical drag, double-click to type; pan uses the center-detent slider.
- Zoom + scroll keep loop flags and selection anchored to sample positions, not pixels. Audition
  respects the current loop mode.

---

## 9. Keyboard / navigation notes

Space = audition play/stop; Esc = stop; `[`/`]` nudge loop start/end; `Cmd+A` select all; standard
`Cmd+X/C/V` cut/copy/paste; `Cmd+Z` undo through the shared document history; `+`/`-` zoom; arrows scroll when zoomed;
Up/Down move the sample list; the computer keyboard plays audition notes when the waveform area has
focus.

---

## 10. AppKit implementation notes (for a future PR)

- Fixed-size window first pass (design the waveform view to already cope with width changes, since
  resizable is the likely next step); single shared instance, menu-toggled.
- **Waveform canvas:** a custom view drawing a downsampled min/max representation as a single line;
  handles selection drag, loop-flag drag, zoom, and scroll. Downsample for display — never draw
  per-sample at full length.
- **Knobs / pan slider / LEDs / switches / segments:** reuse the shared control library.
- **Edit bank + generators:** wire each op through
  `EditableDocumentEditCoordinator.applyEdit` as one labeled whole-document undo step; keep DSP generation off the audio
  thread; confirm-on-replace for generators and Clear.
- **Audition:** route play through the existing isolated preview surface, honoring loop mode. Do not
  create a new playback path or touch mixer timing.
- **Format readout:** display-only from existing metadata; no conversion in v1.0.

### Suggested PR sequence

Prerequisite done: document applyEdit/undo funnel with capped whole-value snapshots.

1. Window shell + menu toggle.
2. Sample list + name/format readout bound to document.
3. Waveform view (read-only render + zoom/scroll).
4. Waveform selection + loop-flag drag.
5. Loop cluster (mode/start/end/length) wired.
6. Sample params (volume/pan/rel/finetune) wired.
7. Audition (play/stop honoring loop) via preview path.
8. Edit bank — trim/crop first, then cut/copy/paste.
9. Normalize/reverse/fade with one atomic whole-document undo step per operation.
10. Waveform generators (confirm-on-replace).
11. File load/export.

---

## 11. Testing / manual verification

Screenshot before/after per PR. Waveform: render matches data; selection and loop flags map to correct
sample positions across zoom/scroll; length = end − start stays consistent. Loop: mode changes
audition audibly; flags and steppers stay in sync. Destructive ops produce the expected buffer change
and are reversible by Undo; Generate/Clear confirm before replacing; Normalize peaks at full scale
without clipping. Params affect audition as expected; format matches metadata. Audition uses the
isolated preview path only and does not perturb mixer timing or the tracker viewport; large samples
stay responsive (downsampled draw).

---

## 12. Risks and open questions

- Waveform rendering performance on long samples is the main perf risk — downsample for display, avoid
  per-sample work.
- Destructive edits without robust undo are dangerous — keep each operation to one atomic snapshot
  and retain confirm-on-replace for generators and Clear.
- Loop-flag vs selection drag can collide — give flags their own hit zones.
- Open: loop end vs length as the primary editable field.
- Open: when to promote the window to resizable (the waveform benefits first).

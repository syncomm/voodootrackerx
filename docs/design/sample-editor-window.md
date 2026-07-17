# VoodooTracker X — Sample Editor Window

**Window:** Sample Editor (independent floating utility window).
**Fixed size (first pass):** ~940 × 560.
**Visual source of truth:** `assets/mockups/sample-editor-v1.html`.
**Reference:** FastTracker II sample editor, reinterpreted in VTX's tactile language.
**Status:** The fixed mockup-aligned shell, read-only metadata binding, bounded
waveform overview, and display-only loop visualization are implemented. Sample,
loop, and PCM mutation remain deferred.

For appearance, hierarchy, geometry, labels, grouping, placement, spacing, and
proportions, `assets/mockups/sample-editor-v1.html` takes precedence over this
document. This prose remains authoritative for behavior, architecture, state,
and safety. If they conflict visually, follow the HTML and update this document;
do not substitute a generic AppKit inspector.

See `docs/design/editor-window-design-overview.md`,
`docs/design/editor-control-vocabulary.md`, and
`docs/design/editable-document-save-export-model.md`.

---

## 0. Current read-only foundation

`Window > Sample Editor` opens one active fixed utility window/controller at a
time, reusing it while open. It preserves normal close, Command-W, activation,
and movement. It follows the
canonical instrument/sample selection shared by the main control panel and
Instrument Editor. Represented-row selection remains non-mutating, creates no
undo, and works for loaded and editable documents, including during playback.

The display shows exact available instrument/sample identity, frame length, bit
depth, volume, panning, finetune, relative note, and loop mode/range. It uses a
bounded min/max waveform projection and safe display-only no/forward/ping-pong
loop markers/region. Empty documents and unrepresented slots remain honestly
empty. The mockup's values are illustrative: FORMAT reports represented bit
depth and mono without treating playback-policy `baseSampleRate` as source-rate
metadata or fabricating 44.1 kHz.

Loaded modules remain read-only. Editable documents and editable copies are
also display-only in this window. Existing Instrument Editor metadata edits and
undo/redo refresh the readouts, but the Sample Editor adds no document or undo
mutation. Waveform selection/interaction, loop and PCM editing, processing,
generation, import/export, and Sample Editor audition are deferred; future
controls shown to preserve the mockup hierarchy stay disabled and inert.

---

## 1. Future purpose and mental model

The eventual Sample Editor supports **direct waveform editing** of a single
sample: see the waveform, select a region, set loop points, and apply edits
(trim, crop, normalize, reverse, fade) or generate a basic waveform from
scratch. It is the most "hardware bench" of the three windows — a big display
with controls underneath.

Mental model: **the waveform is the document.** Everything else (loop cluster,
sample params, edit bank, generators, file) acts on the waveform or the current
selection.

The broader v1.0 direction includes **destructive editing** (with undo) and
**waveform generators**, but neither is part of the current read-only foundation.

---

## 2. Future primary user workflows

1. **Audition + set loop:** select a sample → play → drag loop start/end flags on the waveform → pick
   loop mode (None / Forward / Pingpong) → audition again.
2. **Trim/crop:** drag a selection → Crop (keep selection) or Trim (drop silent ends).
3. **Clean up:** Normalize; Fade In/Out; Reverse; Cut/Copy/Paste between regions or samples.
4. **Generate from scratch:** clear → Generate sine/square/triangle/saw/noise → shape → set a loop.
5. **Tune for the keymap:** set relative note + fine tune; set sample volume/pan.

---

## 3. Future functional region inventory

This inventory is conceptual only; it cannot override the refined HTML mockup's
visual geometry. The HTML establishes a header, samples list, dominant waveform
panel, loop and sample-parameter panels, generate/file banks, and a full-width
edit bank. The current read-only waveform uses an amber min/max projection on
graphite with an indigo loop region and red loop-point flags. The signature
SAMPLE PARAMS **VOLUME** knob carries the larger toothed halo. Future controls
remain visible but inert until their separately scoped milestones.

---

## 4. Future control groups

- **SAMPLE list:** scrollable sample slots; fills its box; selection drives the editor.
- **NAME / FORMAT / AUDITION:** editable name; read-only format (bit depth · channels, plus source
  rate only when represented honestly);
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

## 5. Broader v1.0 editing target

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

## 8. Future interaction notes

- Click-drag on the waveform creates a selection; most edits act on the selection, or on the whole
  sample if none. Loop flags drag separately from the selection (give them their own handles).
- Loop start/end are exact steppers **and** draggable flags; length is derived (end − start).
- Destructive ops push a single undo step (v1.0); generators and Clear confirm before replacing;
  Normalize peaks at full scale without clipping; Reverse/Fade act on the selection.
- Knobs: vertical drag, double-click to type; pan uses the center-detent slider.
- Zoom + scroll keep loop flags and selection anchored to sample positions, not pixels. Audition
  respects the current loop mode.

---

## 9. Future keyboard / navigation notes

Space = audition play/stop; Esc = stop; `[`/`]` nudge loop start/end; `Cmd+A` select all; standard
`Cmd+X/C/V` cut/copy/paste; `Cmd+Z` undo through the shared document history; `+`/`-` zoom; arrows scroll when zoomed;
Up/Down move the sample list; the computer keyboard plays audition notes when the waveform area has
focus.

---

## 10. AppKit implementation notes (for a future PR)

- Fixed-size window first pass (design the waveform view to already cope with width changes, since
  resizable is the likely next step); one active presenter-owned controller,
  reused while open.
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

1. Done: mockup-aligned shell, canonical selection, and exact read-only metadata.
2. Done: bounded read-only waveform projection and display-only loop overlay.
3. Editable loop mode and range behind `applyEdit`.
4. Sample params (volume/pan/rel/finetune) wired.
5. Waveform selection and separately scoped PCM edit operations.
6. Audition through the existing isolated preview path.
7. Waveform generators with confirm-on-replace.
8. File load/export in separately scoped import/export milestones.

---

## 11. Testing / manual verification

For the current foundation, verify the single-window lifecycle, canonical
selection, exact metadata/empty states, bounded deterministic waveform
projection, safe loop geometry, and non-mutation. Compare the app side by side
with `assets/mockups/sample-editor-v1.html`; keep screenshots under `/tmp`.

Future editing PRs must additionally prove that selection and loop flags map to
the correct sample positions, each destructive operation produces one reversible
undo step, format values remain honest, and audition reuses the isolated preview
path without perturbing mixer timing or the tracker viewport.

---

## 12. Risks and open questions

- Waveform rendering performance on long samples is the main perf risk — downsample for display, avoid
  per-sample work.
- Destructive edits without robust undo are dangerous — keep each operation to one atomic snapshot
  and retain confirm-on-replace for generators and Clear.
- Loop-flag vs selection drag can collide — give flags their own hit zones.
- Open: loop end vs length as the primary editable field.
- Open: when to promote the window to resizable (the waveform benefits first).

---

## 13. Adjacent Instrument and performance direction

The Instrument Editor piano is mapping-first and audition-second across the
96-note map. A default full-range Sample 1 mapping stays neutral; non-default
assignments may later use muted sample-number labels/colors, the selected sample
gets stronger persistent emphasis, and audition keeps a distinct transient
pressed-key layer. Read-only polish may precede mutation. Keymap editing waits
for stable sample-palette and Sample Editor foundations, then uses
`applyEdit`/undo with `instrument-envelopes-keymap.xm` as the public reference.
See `docs/design/instrument-editor-window.md`.

A larger Performance Keyboard/Pad is post-v1 or Pro/AUv3 work. Prefer a
modeless macOS utility panel first; later main-window or iPad touch surfaces may
reuse the same performance-state model. This does not authorize a current
tracker-main-window, logo, or viewport redesign. See
`docs/decisions/011-post-v1-auv3-tracker-instrument-direction.md`.

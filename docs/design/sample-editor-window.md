# VoodooTracker X — Sample Editor Window

**Window:** Sample Editor (independent floating utility window).
**Fixed size (first pass):** ~940 × 560.
**Visual source of truth:** `assets/mockups/sample-editor-v1.html`.
**Reference:** FastTracker II sample editor, reinterpreted in VTX's tactile language.
**Status:** The fixed mockup-aligned shell, canonical selection, sample display,
waveform/loop overview, stopped-editable empty-S01 SINE, and
WAV/AIFF/AIFC/native-FLAC LOAD into empty or represented destinations are
implemented. Other sample mutation remains deferred. Header AUDITION directly
previews the selected sample at C-4.

For appearance, hierarchy, geometry, labels, grouping, placement, spacing, and
proportions, `assets/mockups/sample-editor-v1.html` takes precedence over this
document. This prose remains authoritative for behavior, architecture, state,
and safety. If they conflict visually, follow the HTML and update this document;
do not substitute a generic AppKit inspector.

See `docs/design/editor-window-design-overview.md`,
`docs/design/editor-control-vocabulary.md`, and
`docs/design/editable-document-save-export-model.md`.

---

## 0. Current foundation, SINE, and audio LOAD

`Window > Sample Editor` opens one active fixed utility window/controller at a
time, reusing it while open. It preserves normal close, Command-W, activation,
and movement. A compact, non-editable instrument popup in the SAMPLES panel and
the sample rows follow the canonical instrument/sample selection shared by the
main control panel and Instrument Editor. Changing either selection is UI-only,
creates no undo, works for loaded and editable documents including during
playback, cancels stale preview through the existing canonical path, and reuses
the existing sample-slot normalization policy. External selection refreshes the
popup without emitting another callback, and selected sample rows scroll into
view when needed.

The display shows exact available instrument/sample identity, frame length, bit
depth, volume, panning, finetune, relative note, and loop mode/range. It uses a
bounded min/max waveform projection and safe display-only no/forward/ping-pong
loop markers/region. The selected row, header identity, metadata, waveform, and
loop display are built from the same represented sample. An empty sample name
shows `(unnamed sample)` rather than absence; no represented sample clears every
sample surface. Empty documents and unrepresented slots remain honestly empty.
File New therefore selects represented I01 while showing `No represented sample`,
an empty waveform/loop/metadata surface, and the canonical empty S01 destination
owned by the document rather than a fabricated sample row.
The mockup's values are illustrative: FORMAT reports represented bit depth and
mono without treating playback-policy `baseSampleRate` as source-rate metadata
or fabricating 44.1 kHz.

Loaded modules remain read-only. SINE is enabled only for stopped editable empty
S01. It cancels preview, validates owned PCM off the render callback, commits one
`Generate Sine Sample` edit, and refreshes all editors without auto-audition.
LOAD is enabled only for a stopped editable empty S01 or represented selected
sample and is disabled during an active import. Its single-file panel accepts
WAV/WAVE, AIFF/AIF, AIFC, and native FLAC and never accepts directories. A
format-neutral facade validates the actual container identity, rejects
Ogg-FLAC and recognized extension/container mismatches, and dispatches to the
existing decoder. LOAD offers occupied Replace/Add as New/Cancel, then stereo
Mix to Mono/Left/Right after
inspection, and decodes/normalizes off the main thread while showing an
indeterminate state. The main thread revalidates document identity/revision,
selection, sample count/capacity, destination occupancy, stopped transport, and
operation token before one labeled edit. Commit cancels stale
preview once, refreshes all editors, and does not auto-audition. Other
states/generators stay disabled; preview/runtime architecture is unchanged.
AUDITION is non-mutating for loaded/read-only and editable samples; it sends the
selected slot directly at C-4 through the persistent stream—not the keymap—and
reuses sample planning. Exact lifecycle release drives its glyph/LED. Note
selection and natural-completion notification remain future work; no polling is
used.

### From-scratch creation/import contract

The Sample Editor owns sample identity, selection within the current
instrument, import/generation, waveform and loop metadata, parameters, and
later PCM operations. Its instrument popup selects context but never creates
an instrument. The current audio workflow fills only empty S01 on a zero-sample
instrument or offers Replace Current Sample/Add as New Sample/Cancel for the
represented selected sample. Add appends and selects the next canonical Sxx but
never redirects a stale result or changes the keymap. Sample Editor AUDITION
plays that selected slot directly; Instrument Editor audition and pattern
playback remain keymap-driven until future explicit mapping.

SINE repeats a precomputed 32-value integer table at amplitude 12,000 exactly
512 times for 16,384 frames, with neutral tuning and a full forward loop. PCM SHA-256:
`ac9e9e7dbfbf285d7ca2d98cabf2ed57e5c3ac9e53f1ec01ba4813c02d4a7b91`.
At C-4's 8,363 Hz base rate the tone is 261.34375 Hz, within 0.5 Hz (about 1.87
cents low) of 261.625565 Hz; C-5 is 522.6875 Hz. The all-zero map stays neutral.

The UI-independent import facade identifies RIFF/WAVE, FORM/AIFF, FORM/AIFC, and native `fLaC`
from their headers and dispatches to the existing bounded decoders. WAV supports
mono/stereo 8/16/24/32-bit integer PCM, Float32 PCM, and matching extensible
forms through chunked `AVAudioFile` reads. AIFF supports signed 8/16/24/32-bit
PCM; AIFC supports big-endian `NONE`/`twos` and little-endian `sowt`. Native
FLAC foundation supports only 16/24-bit mono/stereo sources. It validates
STREAMINFO rate, channels, depth, known positive frame count, and the shared
16,777,216-frame cap before bounded Apple `ExtAudioFile` decoding. Valid 8-bit
FLAC is unsupported by that decoder and is rejected during preflight; every
untested depth and Ogg-FLAC are also rejected. Mix to
Mono averages `0.5 × (left + right)`; Left and Right select their channel, while
mono treats channel 0 as both. Results are clamped, quantized to canonical
16-bit PCM, named from the 22-byte XM-safe filename stem, tuned from the
8,363 Hz C-4 reference, and default to no loop. The cap is 16,777,216 frames
(64 MiB of mono Float32). LOAD installs the complete candidate as
document-owned PCM through one undoable edit; the source path is not retained
and Export XM/reopen uses the existing sample writer. Format metadata including
WAV cue/`smpl`/broadcast fields, AIFF/AIFC MARK/INST/COMT/NAME/AUTH/ANNO,
and FLAC tags, pictures, cues, seek tables, application/padding blocks, ReplayGain,
embedded names, and loops remains deferred. The Sample Editor panel still lists
every currently supported lossless import format. Add as New Sample and S02+
are current; delete, clear, reorder, duplication, standalone New Sample, keymap
editing, and global import/drop creation remain deferred.
Square/pulse, triangle, saw, and noise remain future generators.
First-sample import/generation maps all 96 notes and becomes immediately
auditionable in one `applyEdit` action. See
[ADR 012](../decisions/012-from-scratch-instrument-sample-composition-model.md).

### Post-alpha lifecycle selection contract

Clear/Duplicate/Move/Swap remain unimplemented. Future Clear Sample is
non-compacting: removing represented Sxx leaves that zero-based identity absent,
keeps every later represented sample index and all 96 keymap values unchanged,
and makes any route to Sxx unavailable rather than falling back to S01 or the
first playable sample.

Editable selection is stored in the `BlankTrackerDocument` value, while normal
row selection remains a non-editing UI gesture. Clearing the selected Sxx must
carry the same selection into the new whole-document snapshot so the editor
shows that exact empty destination; clearing another slot must not change
selection. Undo and redo then restore the exact prior/new selection with the
same whole-snapshot policy already used by Add as New. The current
available-slot normalizer may choose the first represented sample (or S01 when
none exists) during instrument/copy transitions; a same-instrument lifecycle
action must not call that normalizer merely because its target became empty.

Today the lists expose represented samples and the special empty S01 of a
zero-sample instrument. They do not yet render an interior empty row beside
later represented rows. That presentation and the sparse XM round-trip
foundation are prerequisites, not permission to redirect selection or add
Clear UI in this characterization slice. See ADR 012's post-alpha lifecycle
boundary.

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
additional **waveform generators**; SINE is the only current generator. Current
audio LOAD supports import/replace/append only; it adds no direct waveform editing.

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
- **FILE:** sample LOAD (WAV/AIFF/AIFC/FLAC) / EXPORT / CLEAR / REPLACE — prominent, since sample editing is
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
3. Done: compact canonical instrument selector and coherent represented/unnamed/absent sample identity.
4. Done: separate empty-instrument/S01 creation through `applyEdit`; this window
   refreshes to the selected instrument while keeping all sample surfaces empty.
5. Editable loop mode and range behind `applyEdit`.
6. Sample params (volume/pan/rel/finetune) wired.
7. Waveform selection and separately scoped PCM edit operations.
8. Audition through the existing isolated preview path.
9. Waveform generators with confirm-on-replace.
10. File load/export in separately scoped import/export milestones.

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

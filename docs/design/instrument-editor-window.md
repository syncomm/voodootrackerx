# VoodooTracker X — Instrument Editor Window

**Window:** Instrument editor (independent floating utility window).
**Implemented shell size:** 920 × 638.
**Mockup:** `assets/mockups/instrument-editor-v1.html`.
**Reference:** FastTracker II instrument editor, reinterpreted in VTX's tactile language.
**Status:** The fixed-size v1-mockup shell binds to document/selection state. Represented instrument
NAME and the selected represented sample's exact XM panning byte are editable only in stopped
editable documents and route through applyEdit/whole-snapshot undo.
The existing VOLUME knob now edits the selected represented sample's exact XM `0...64` value under
the same stopped/editable policy; its bounded control emits valid values and the mutation API rejects
out-of-range requests. Subsequent playback uses the unchanged adapter gain mapping.
The existing FINETUNE knob now follows the same policy for the exact XM signed-byte range
`-128...127`, commits once at mouse-up, and uses the unchanged pitch adaptation on later playback.
The existing REL NOTE stepper now edits the same signed-byte range through one labeled applyEdit
commit per click and uses that unchanged pitch adaptation.
Represented XM autovibrato bytes are shown on the disabled VIBRATO controls. Loaded modules,
playing documents, and every unimplemented mutation control remain read-only. Focused unmodified
computer note keys outside text responders reuse the tracker map and isolated preview path;
the three-octave on-screen keyboard defaults to C-2...B-4, shifts by octave across the 96-note map,
and auditions exact primary-click pitches through the same path without changing selection. Accepted
focused computer notes use that same pressed-key visual only while visible; generation identity keeps
mouse/computer replacement monophonic and stale releases harmless. The committed-ownership strip
immediately above the piano projects the exact same `InstrumentKeyboardVisibleRange`; the canonical
96-note document map remains authoritative. Range navigation refreshes both surfaces as session UI
state with no document/undo mutation. `MAP RANGE…` maps the selected represented nonempty sample
through an explicit inclusive C-0...B-7 sheet and one undo action. The strip has no pointer interaction;
graphical range selection, drag-to-paint, and automatic assignment remain deferred. Instrument/sample rows,
including eligible canonical empty Sxx destinations, share canonical control-panel selection in loaded/editable
and stopped/playing states. Selection
is non-mutating, creates no undo, cancels stale preview before context changes, and drives metadata;
selected sample is editing focus only, while audition uses instrument plus note and the keymap. An empty selected
row owns no `PlaybackSample`, clears represented metadata/default displays, and keeps VOLUME, PAN, FINETUNE,
REL NOTE, and `MAP RANGE…` unavailable. Notes mapped to that empty identity remain unavailable with no fallback;
notes mapped to represented Sxx continue to resolve independently of the selected row.
Transport gates mutation only. The editor closes normally through its red close button
or Command-W and reopens as one clean presenter-owned window. Broader sample/XI,
envelope/keymap, waveform, and
autovibrato playback work remains future scope. Represented XM panning-envelope data is
shown through a local display-only VOL/PAN selector using the shared graph and readouts, while
document/undo and playback state remain untouched. Parser architecture,
broad writer/export behavior, tracker viewport, and audio backend behavior are unchanged.

See `docs/design/editor-window-design-overview.md`, `docs/design/editor-control-vocabulary.md`, and
[ADR 013](../decisions/013-visible-keymap-ownership-projection.md).

### Implemented foundation and first metadata edit

`Window > Instrument Editor` opens one reusable AppKit utility window using the mockup's header,
left instrument/sample lists, center envelope panel, right vibrato/defaults panels, and bottom note
keymap hierarchy. It follows the current loaded module, editable document, or editable copy plus the
main control-panel instrument and sample selection. The shell shows represented instrument
number/name/sample count, sample slot/name/length/loop mode and range/volume/panning/relative
note/finetune,
an immutable selected volume/panning-envelope preview, and represented note-to-sample ranges. Missing data has an
explicit empty state. NAME is inline-editable only for represented instruments in stopped editable
documents; it uses XM's 22-byte constraint and one labeled `Rename Instrument` undo step. PAN is the
first editable sample metadata field and commits one `Change Sample Panning` action at mouse-up.
VOLUME commits one exact `Change Sample Volume` action at mouse-up and supports undo/redo; loaded
modules and active playback keep it disabled. FINETUNE commits one exact `Change Sample Finetune`
action at mouse-up; REL NOTE commits `Change Sample Relative Note` with the same gating and signed
readout. No pitch formula, runtime engine, DSP,
gain-law, or scheduling logic changed.
Undo/redo refresh this window and the main control panel. Sample-header panning initializes the next
focused preview/runtime/export trigger; instrument autovibrato remains runtime-inert. Panning-envelope metadata is preserved but not yet
applied to playback; its VOL/PAN selector changes only local display mode, and every envelope edit
control remains disabled/inert alongside XI and loaded-module NAME.

The sample list consumes the shared UI-independent slot projection. Editable lists are contiguous from S01 through
the highest represented, exact-map-referenced, or valid selected identity, with a hard S16 cap; zero-sample
instruments show empty S01. Remaining capacity does not advertise a future append row; occupied LOAD -> Add as New
creates the next represented identity before the row appears. Loaded lists show represented identities plus only canonical zero-payload
gaps proven by source provenance, and never a synthetic append row. Empty rows are selectable editing focus during
stopped or playing state, are labeled as empty destinations for accessibility, and create no document revision or
undo entry.

Keymap assignment uses zero-based map indices `0...95` (XM notes `1...96`,
C-0...B-7) and zero-based sample indices displayed as S01...S16. It requires
the stopped editable selected instrument and a nonempty represented selected
sample, captures document/revision/target identity, and creates at most one
`Map Sample to Note Range` action. Its manual From/To controls use canonical
note names and inclusive bounds; deterministic defaults use a focused audition
note, selected octave, then C-4...B-4. Confirmation reads the current selectors.
`InstrumentEditorVisibleKeymapProjection` clips that canonical map to the same
`InstrumentKeyboardVisibleRange` passed to the piano, yielding one committed-ownership cell per visible
note and contiguous display segments. It is a pure projection and returns no hit target. Segment edges
reuse `InstrumentEditorKeyboardLayout` key-frame midpoint boundaries: the outer notes use the keyboard
content edges, and every interior boundary is the midpoint between neighboring note-key centers. There
is no independent full-96 proportional geometry. Range navigation rebuilds both views from the same
range without changing the document, revision, history, or selection; loaded read-only modules use the
same projection while `MAP RANGE…` remains disabled. No-ops create no history, and assignments outside
the inclusive edit range remain exact. Tests pin C-0=0, C-4=48, C-5=60, B-5=71,
C-6=72, and B-7=95, including exactly 12 changed entries for C-5...B-5 and exact
C-5/B-5/C-6 ownership boundaries independent of selected-sample editing focus.
The header reads `VISIBLE RANGE OWNERSHIP · USE MAP RANGE… TO EDIT · PIANO AUDITIONS`.
Labels describe only visible segment portions; narrow segments abbreviate to Sxx or omit interior text.
One canonical resolver validates the exact 96-entry map and represented playable
sample for Instrument Editor audition, pattern-entry audition, editable playback,
and adapter planning. It never reads or mutates selected-sample UI state. Sample
Editor audition remains direct-selected-sample.

The close lifecycle remains standard AppKit behavior: the red close button and Command-W close only
the utility window, the Window menu recreates one controller/router when asked, and close cancels any
computer or graphical preview before detaching its handlers. The panel matches the Song/Order Editor's
activating utility-window configuration, and its audition router inspects only keyboard events so
AppKit handles mouse activation and the standard traffic lights without interception. Editable-copy
confirmation remains a document-level sheet on the main tracker window. When invoked while the
Instrument Editor is key, the floating panel is temporarily ordered behind the sheet and restored
after dismissal rather than becoming the sheet owner. Open/reopen installs the content view as the non-editing initial
responder, leaving NAME unselected and audition immediately eligible; explicit NAME focus still uses
the normal field editor and suppresses audition until editing ends. Preview activity is independent of transport playback, so it
does not alter NAME/PAN/VOLUME/FINETUNE/REL NOTE eligibility. Metadata changed during or after a
preview is read on the next audition trigger; held-note live modulation and automatic retrigger remain
out of scope. Focused computer and graphical audition resolve the XM keymap sample before applying its pan.

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

### From-scratch composition contract

The Instrument Editor owns instrument identity, sample palette/slots, keymap,
envelopes, autovibrato, default sample metadata, and note audition. File New now
represents unnamed zero-sample I01 with selected empty S01. `Edit > New
Instrument` appends after the highest represented one-based Ixx, creates and
selects an unnamed instrument with an honest empty S01 destination, and reveals
this window through one `applyEdit` action. It does not fill sparse holes in the
current dense palette/writer model and must not create PCM or sample
metadata. The first represented sample maps across all 96 notes; later samples
do not alter that map implicitly. The Sample Editor's implemented SINE action
fills empty S01 with a deterministic document-owned sample and establishes the
explicit all-zero map; the resulting single full-range S01 assignment stays
visually neutral and is available to focused and graphical audition after the
shared refresh. Clear preserves slot numbering, while future
move/swap remaps pattern references transactionally. See
[ADR 012](../decisions/012-from-scratch-instrument-sample-composition-model.md)
for the canonical lifecycle, dependency order, and release gate.

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
│ │ visible band: S01 | S02 | S01     [3-octave keyboard, click/drag=audition] │ │
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
  showing committed ownership for exactly that visible range; click/drag the piano to audition and
  use `MAP RANGE…` for manual selected-sample assignment.

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
- Keymap: primary press auditions that exact note with the current instrument; dragging across keys
  releases/presses notes for audition. The noninteractive strip reports committed ownership for the
  piano's exact visible range using the same geometry. `MAP RANGE…` assigns the selected represented
  sample from explicit manual selectors. Future graphical selection must operate directly on the
  visible piano or use an explicit selection mode with an unambiguous scale; drag-to-paint and
  automatic assignment remain future work.
- All audition goes through the isolated preview path — never full-song playback.

### Implemented polish: transient live numeric readouts with one commit

For VOLUME, FINETUNE, and PAN, the numeric and accessibility values update
continuously during drag so precise values remain visible. That
display is transient UI preview state: the underlying document still commits
one `applyEdit` mutation at mouse-up or the existing commit boundary, rather
than creating one mutation and undo entry per intermediate value. The commit
creates one undo action.

- A no-op drag creates no history.
- Escape or another future cancel gesture should restore the original displayed
  value.
- Typed numeric entry remains available for exact values.
- Held previews are not live-modulated or retriggered; the persistent preview
  stream remains unchanged and the next trigger uses the committed value.

Selection, document, transport, mode, deactivation, disable, and close
transitions cancel stale drag state and restore the canonical committed display.

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
- **Envelope canvas:** the current custom view draws selected represented volume or panning points,
  enabled/sustain/loop context, and returns no hit target. Future editing may add drag without creating
  per-point subviews.
- **Knobs / pan slider / LEDs / switches / segments:** reuse the shared control library
  (`docs/design/editor-control-vocabulary.md`).
- **Keymap:** one shared `InstrumentKeyboardVisibleRange` and `InstrumentEditorKeyboardLayout` drive
  the piano and committed-ownership strip. Strip boundaries use the midpoint between neighboring
  key frames, while the keyboard retains black-key-first hit testing and exposes semantic press/release
  intents to isolated preview. The strip rejects hit testing. The explicit
  range sheet calls the existing edit coordinator once; any future graphical
  assignment must reuse that path and align with the visible keyboard or an
  explicit selection mode.
- All future edits must submit a new whole document through
  `EditableDocumentEditCoordinator.applyEdit`; direct palette write-back is not
  an editor integration path; the implemented name field follows this rule.
  Do not alter the audio backend, mixer, parser, or tracker viewport.

### Suggested PR sequence

1. Done: v1-mockup window shell + menu command + read-only instrument/sample-slot,
   volume-envelope-preview, and note-map-range binding.
2. Done: add the document applyEdit/undo funnel required before mutation.
3. Done: represented instrument NAME editing.
4. Done: sample panning model/load/editable-copy/Export XM round-trip plus read-only PAN display.
5. Done: autovibrato round-trip plus read-only display.
6. Done: runtime-inert panning-envelope model/load/editable-copy/Export XM round-trip.
7. Done: read-only VOL/PAN switch + represented panning-envelope preview.
8. Done: selected represented sample PAN mutation behind applyEdit/undo.
9. Done: selected represented sample VOLUME mutation behind applyEdit/undo.
10. Done: selected represented sample FINETUNE mutation behind applyEdit/undo.
11. Done: selected represented sample REL NOTE mutation behind applyEdit/undo.
12. Done: focused-window computer-keyboard audition through the isolated preview path.
13. Done: audition-only on-screen keyboard interaction.
14. Done: canonical instrument/sample list selection without document or undo mutation.
15. Done: resolved-sample panning in focused audition, runtime playback, and product audio export.
16. Done: create an unnamed instrument with honest empty S01 through `applyEdit`.
17. Envelope editing (points, sustain, loop, add/del) wired.
18. Vibrato + remaining defaults controls wired.
19. Done: UI-independent keymap range assignment through `applyEdit`.
20. Done: explicit selected-sample inclusive note-range assignment sheet.
21. Done: committed-ownership-only visible-range strip aligned to the audition piano; graphical
    selection deferred.
22. Future: drag-to-paint and automatic assignment.

---

## 11. Testing / manual verification

For the implemented slice, verify empty/default, loaded-module, editable-copy, playing, and
selection-change states; confirm NAME and represented-sample VOLUME, FINETUNE, and PAN are editable only in a stopped
editable document; and confirm edit/undo/redo refresh both the window and control panel. Export a
supported represented instrument to a temporary XM and reload its name. For sample panning, confirm
a non-center value displays exactly, PAN stays disabled for loaded/playing/empty states, and an edit
survives Export XM/reopen. Confirm left/center/right samples are audible in focused computer and graphical
audition and normal playback, and that an edit changes only the next trigger. For relative note and finetune, confirm signed endpoints and intermediate values survive,
editing is blocked during playback, and undo/redo restore the corresponding later playback pitch.
With the Instrument Editor focused outside NAME, verify both note-key rows, octave and
sample selection, repeat suppression, and matching key release; confirm NAME typing and standard
shortcuts win and pattern/cursor/undo state does not change. On the on-screen keyboard, verify white
and black clicks, boundary precedence, drag within/between/outside keys, matching mouse-up, pressed
visuals, note-map sample splits, and cleanup on selection/deactivation/close.
Click every represented row in loaded, editable-copy, stopped, and playing states; confirm shared
highlights, metadata, honest empty sample states, preview cancellation, and no undo. Transport must
gate mutation, never row selection. Graphical keys must not change the explicit sample selection.
Verify autovibrato likewise survives while VIBRATO remains disabled
and playback/audition output is unchanged. Verify panning-envelope graph/readouts in loaded and
editable-copy states, clean disabled/empty states, local VOL/PAN switching across undo/redo, and
unchanged playback. For range assignment, begin with all notes on S01, select
represented S02, use the manual selectors to map C-5...B-5, and show C-4...B-6.
Confirm the 36-note strip reads B-4 as S01, exactly 12 semitones C-5...B-5 as
S02, and C-6 as S01. Its C-5 edge must equal the piano's C-5 boundary; its B-5
edge and the start of C-6 must equal the piano's C-6 boundary across tested view
widths/backing scales. Navigate the piano range and confirm both surfaces stay
identical without revision, history, or selection changes. Confirm pointer input
on the strip creates no state or sheet prefill; verify read-only projection with
`MAP RANGE…` disabled, B-5/C-6 audition and playback, selected-sample independence,
one undo/redo action, and Export XM/reopen. Keep screenshots/exports local and untracked.

Loop, PCM, waveform, envelope, drag-to-paint/automatic keymap mapping, XI, and
broader sample-import editing remain future work.

For later interactive slices, screenshot before/after per PR and verify the surface reads as calm at
fixed size. Envelope: points
add/drag/delete; sustain/loop markers track point indices; VOL/PAN swaps cleanly; fadeout maps
correctly. Knobs ↔ segments stay in sync; double-click entry clamps to valid ranges; relative note +
fine tune affect audition pitch. Keymap assignment: color band matches committed assignments and the
manual sheet updates the exact inclusive range; click audition already uses the preview path. No change to
mixer timing, audio backend, or tracker viewport while open.

---

## 12. Risks and open questions

- Envelope point editing is the highest-complexity custom view — land it read-only first, then add
  editing, to stay narrow.
- Too many knobs could tip into "intimidating" — grouping + the single signature knob are the
  mitigations; verify with a fresh user.
- A future graphical keymap selector must use the visible piano's exact range and geometry or provide
  an explicit, unmistakable mode; the ownership strip itself remains noninteractive.
- Open: secondary cluster vs. explicit "advanced" disclosure for vibrato/relative note.
- Open: envelope predefs in v1.0 or later (assumed later).

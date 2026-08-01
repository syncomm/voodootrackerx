# Editable Document Save/Export Model

Status: design plus implemented initial Export XM and explicit editable-copy
slices. This note defines product and architecture rules for save/export work.
The app now has Export XM for stopped editable documents, including existing
palette/sample payloads where the editable model safely represents XM-derived
signed PCM, and `File > Make Editable Copy` for supported stopped loaded XM
modules. The Instrument Editor shell and represented instrument-name editing
are implemented outside this save/export design. The active sample model,
loader, editable-copy/snapshot path, and writer now preserve exact XM sample
panning bytes, exact instrument panning-envelope fields, and exact instrument
autovibrato bytes. The Instrument Editor edits selected-sample panning only in
stopped editable documents/copies through applyEdit/undo; loaded modules remain
read-only, and panning stays runtime-inert. Autovibrato and panning envelopes
remain playback/audition-inert. A
selected represented sample's exact XM `0...64` volume is also editable only while stopped through
the same applyEdit/undo funnel, survives Export XM/reopen, and reaches subsequent playback through
the existing gain mapping without runtime engine, DSP, or scheduling changes. Exact signed-byte XM
sample finetune (`-128...127`) now follows the same stopped/editable, applyEdit/undo, and Export
XM/reopen boundary; later playback uses existing pitch adaptation without any pitch-formula,
runtime-engine, DSP, or scheduling change. Exact signed-byte sample relative note now follows that
same boundary and existing pitch path. Inclusive keymap range mutation now uses
the same one-applyEdit boundary; no-ops create no history, and existing editable-copy,
XM, and product-audio export paths preserve or consume the result. Instrument
Editor exposes it through an explicit selected-represented-sample inclusive
C-0...B-7 sheet; selection and assignments outside the range remain unchanged. A
document-level applyEdit/whole-snapshot undo funnel owns replacement. Save, Save As,
loaded-module direct editing, broader instrument/sample mutation, Sample Editor
mutation beyond SINE/import, runtime playback changes, parser architecture changes,
and tracker viewport changes remain unimplemented by this note. The fixed Sample
Editor shell remains outside this design; SINE uses the same snapshot boundary.

The implemented rename and sample-panning edits, plus all future instrument/sample
mutations, submit new editable-document values through that funnel. Its context carries no source
URL, rejects loaded read-only and playback-active states, and does not turn
undo, redo, or export destinations into source-path ownership.

## Purpose

VoodooTracker X now supports a first-pass composition workflow for blank
editable documents, loaded-module-derived clear-song copies, and explicit
loaded-module editable copies. Before file writing exists, the app needs
explicit ownership rules so persistence cannot overwrite a user's opened
source module by accident.

The design goal is to separate three concepts:

- the editable in-memory document the user is composing in
- the loaded read-only module that may have supplied palette/sample data
- an explicit user-chosen output destination for save/export

Loaded modules remain read-only by default. Direct mutation of opened module
files remains blocked. A loaded module can become editable only through an
explicit copy workflow, and that copy must not inherit permission to overwrite
the original source path.

## Document State Model

| State | Editable? | Source/output ownership | Save/export implication |
| --- | --- | --- | --- |
| Blank editable document from `File > New` | Yes | In-memory document with no owned path | Save remains disabled until an owned document format/path exists. Export XM may write a user-chosen new XM file without making that file an owned save path. |
| Editable document derived from Clear Song Data or an editable-copy bridge | Yes | Value-owned copy of editable song/order/pattern state plus safely represented palette/sample data | The source module path, if any, remains external and read-only. Save/export must choose a new destination. |
| Loaded module read-only state | No | External opened module path owned by the user or filesystem, not by VTX | Pattern, song/order, instrument, and sample mutations are blocked. Save must not target this path implicitly. |
| Explicit editable copy of a loaded module from `File > Make Editable Copy` | Yes, after user command | New untitled in-memory editable document derived from the supported loaded XM subset | The original module remains untouched. Save/Save As remain disabled. Export XM must choose a new destination. |
| Future saved/exported editable document state | Yes | User-chosen destination, with ownership made explicit | A native saved state requires a chosen native format/path. Exported XM is a public interchange artifact and should not silently become permission to overwrite an opened source module. |

Current `Edit > Clear Song Data` on a loaded module is an editable-copy bridge
with deliberately narrow semantics: it preserves safely represented
instrument/sample palette data and playable sample payloads where available,
then clears song/order/pattern note data into an editable blank song. It is not
full loaded-module editing.

## From-Scratch Sample Ownership

Imported or generated PCM is copied into the editable document before it becomes
playable. LOAD supports WAV, AIFF/AIFC, and native mono/stereo 16/24-bit FLAC;
all decoders return the same value-owned, canonical 16-bit mono candidate with
no retained source URL. FLAC 8-bit and untested depths plus Ogg-FLAC are
rejected, and FLAC metadata/loops are ignored. LOAD validates container
identity before dispatch, then validates the complete candidate and exact
captured destination before one `Import Audio Sample`, `Replace Audio Sample`,
or `Add Audio Sample` `applyEdit`; failure or stale state leaves the prior document and undo history
unchanged. Implemented SINE generation likewise validates
deterministic PCM before one `applyEdit` commit. The original
sample path is optional provenance, not source/output ownership, and playback,
undo/redo, Export XM, offline audio export, portability, and future AUv3 state
must not depend on that file remaining present.

An empty S01 destination is not a represented sample and carries no PCM or
fabricated sample metadata. File New now owns one such I01/S01 destination, and
New Instrument appends another through one stopped-editable `applyEdit` action.
SINE fills only that selected destination with document-owned 16-bit mono looped
PCM and an all-zero 96-note map; audio LOAD fills it with canonical no-loop PCM
and the same neutral map. Replacing preserves its exact slot; Add appends and
selects the next represented Sxx. Both preserve keymap references and unrelated
instrument data, and Sample Editor can directly audition the selected slot while
pattern/Instrument Editor audition remains keymap-driven. Undo returns to the
exact empty or prior represented state.
The creation/import/export contract,
including the proposed `v0.3.0-alpha.1` gate, is defined by
[ADR 012](../decisions/012-from-scratch-instrument-sample-composition-model.md).
It does not enable Save/Save As or make an export destination an owned path.

## Save, Save As, And Export XM

### Save

`Save` should stay disabled until the app has both:

- a safe owned document path
- a selected document format with compatibility rules

`Save` must never use an opened module's source path just because that module
was loaded. Exporting or deriving an editable copy from a loaded module does not
grant permission to overwrite the source module.

If VTX later chooses a native project format, `Save` may write that owned
format after `Save As` has established ownership. Until that decision exists,
Save should remain unavailable for unsaved editable documents.

### Save As

`Save As...` is the future command for choosing an owned editable-document
destination. It must make ownership explicit in the UI: the user is selecting a
new path controlled by the editable document, not editing the original loaded
module in place.

The first Save As implementation should not be treated as implicit loaded-XM
overwrite support. If the chosen format is native, document format changes need
their own design note, compatibility tests, and migration/update rules. If the
chosen format is XM, the UI still needs to make clear that it is writing a new
editable output, not mutating a source module.

### Export XM

`Export XM...` is the first likely practical file output path for editable
composition data. It should:

- be enabled only for editable documents once implementation exists
- ask the user for an output XM path
- write a new XM file at that chosen destination
- leave any opened source module untouched
- avoid changing the document's ability to Save unless a later design
  explicitly defines exported XM as an owned document path

Export XM is an interchange/export operation, not a promise of arbitrary XM
round-trip parity.

Current behavior: `File > Export XM...` is enabled only for stopped editable
documents, including explicit editable copies, presents a save panel with an
`.xm` destination, writes the current editable XM subset to that explicitly
chosen file, and reports completion or a write failure. The current writer
includes existing palette/sample payloads only when they are already safely
represented as XM-derived signed 8-bit or 16-bit PCM in the editable document
model. Represented zero-sample instruments write only their 29-byte XM
instrument headers; reopen preserves their count, order, and names without
inventing sample headers or PCM. Cancel writes nothing. Loaded read-only
modules and active playback
remain disabled/no-op, Save/Save As remain disabled, and the exported XM file
does not become an owned save path.

Release hardening rejects invalid channel/row dimensions, non-finite PCM,
sparse represented sample order, and unmappable keymaps before destination
replacement. Successful writes remain atomic. Make Editable Copy accepts only
Linear-frequency-table XM because the editable model cannot preserve Amiga-table
semantics; named zero-length sample headers remain outside the represented subset.

### Future Native Project Format

A native VTX project format is deferred. It may be useful later for data that
does not fit classic XM cleanly, but no native format is selected by this note.
Any future native format must follow the repository file-format rules:
document the format change, add compatibility tests, and provide migration
tools if compatibility requires them.

## First XM Export Scope

The first XM writer should be narrow and public-safe:

- export blank editable documents and explicit editable copies
- write the song order table
- write pattern data currently represented by the editable model
- preserve supported note, instrument, volume-column, effect type, and effect
  parameter fields where the editable model already owns them
- preserve timing fields such as BPM and speed where they are already
  represented
- preserve channel count and row count where XM can represent them
- include instrument/sample data only when the editable document has valid
  existing palette/sample payloads
- for existing sample payloads, write represented instrument names, keymaps,
  volume- and panning-envelope fields, exact sample panning, relative-note, and finetune bytes, remaining
  sample-header fields, forward/ping-pong loop metadata, and
  correctly delta-encoded signed 8-bit or 16-bit PCM payloads
- return a writer error rather than guessing when sample source metadata,
  bit depth, duplicate sample slots, loop metadata, or envelope point counts
  cannot be safely represented in the current XM subset
- use generated public fixtures or synthetic editable documents for tests

The first writer does not need full XM feature coverage. It should produce a
valid public XM file for the editable subset that VTX currently understands.

First-writer limitations:

- no guarantee of round-trip parity with arbitrary loaded XM modules
- no full Instrument Editor state beyond fields currently represented by the
  editable document and playback/palette models
- Sample Editor mutation is limited to stopped-editable SINE plus format-neutral
  audio import, in-place replacement, and append-only Add as New
- no panning-envelope playback/editing, vibrato playback/editing, broader loop,
  PCM/waveform, destructive lifecycle, XI import, or arbitrary non-XM-derived
  payload support in the current writer; graphical and automatic keymap mapping remain deferred
- no private corpus dependency
- no generated XM/WAV artifacts committed outside explicit reviewed fixture PRs
- no broad parser/writer architecture rewrite
- no claim of FastTracker II, OpenMPT, or MikMod parity

## Loaded Module Editable-Copy Workflow

Loaded-module editing must stay behind an explicit copy boundary:

1. User opens a module. The loaded module remains read-only.
2. User chooses `File > Make Editable Copy`.
3. VTX creates an untitled editable in-memory copy of supported song/order,
   pattern, instrument, and sample data.
4. The UI communicates that the new document is a copy, not the source module.
5. Save/export writes only to a user-chosen destination.
6. The original opened source module remains untouched.

Current behavior: the command is enabled only for stopped loaded read-only XM
modules that expose representable pattern data through the current metadata
model. It is disabled for already-editable documents, no loaded document,
active playback, missing playback-song state, and unsupported loaded modules.
The resulting document is untitled/in-memory, does not claim the opened source
path, keeps Save and Save As disabled, and can use Export XM when stopped.
The copy workflow preserves parsed instrument/sample palette data where the
current models can represent it safely. Data that VTX cannot yet represent is
diagnosed rather than silently written back in a lossy way.

## Safety And Privacy Rules

- Never write over an opened source module implicitly.
- Never commit generated XM, WAV, app, DMG, ZIP, screenshot, trace, metric log,
  or local report artifacts.
- Never use private modules in automated tests.
- Never reference private/local corpus filenames, titles, or local absolute
  paths in committed docs, tests, scripts, or PR descriptions.
- Export tests must use generated public fixtures or synthetic editable
  documents.
- Local manual smoke may write temporary exports under `/tmp` or another
  ignored local path only.
- Keep private/local reports, screenshots, traces, logs, and listening notes
  out of commits.

## Runtime And Audio Boundary

Save/export is a file-output boundary. It must not change:

- runtime playback behavior
- CoreAudio C mixer scheduling
- `RuntimeCMixerAdapterEventPlan`
- C mixer DSP
- parser architecture
- tracker viewport or static-highlight behavior
- Instrument Editor mutation or Sample Editor behavior

Export validation may later reuse existing offline/public-safe render tooling,
but save/export implementation should not add render behavior unless a focused
future PR explicitly scopes that work.

## Proposed Implementation Slices

Keep future PRs narrow and testable:

1. Done: `app: add editable-document Export XM menu/save-panel shell`
2. Done: `xm: add minimal public-safe XM writer model tests`
3. Done: `xm: write editable blank document XM order/pattern/timing data`
4. Done: `tests: add exported-XM reload smoke using public fixtures`
5. Done: `xm: wire Export XM to writer behind safe file boundary`
6. Done: `xm: write existing palette/sample payloads when available`
7. Done: `app: define explicit loaded-module editable-copy command`
8. Done: `instrument: build Instrument Editor shell/read-only binding`
9. Done: `app: add document applyEdit/undo funnel for future instrument and sample editing`
10. Done: `instrument: add editable instrument metadata foundation behind applyEdit` (NAME only)
11. Done: `instrument: add sample panning model round-trip foundation`
12. Done: `instrument: add panning envelope model round-trip foundation`
13. Done: `instrument: add editable sample panning mutation behind applyEdit`
14. Done: `instrument: add editable sample volume mutation behind applyEdit`
15. Done: `instrument: add editable sample finetune mutation behind applyEdit`
16. Done: `instrument: add editable sample relative-note mutation behind applyEdit`
17. Done: `sample: build Sample Editor shell with read-only waveform binding`
18. Done: `instrument: create empty instrument with S01 through applyEdit`
19. Done: `sample: generate deterministic sine sample into empty S01`
20. Done: `sample: wire Sample Editor WAV load and replace workflow`
21. Done: `sample: add AIFF/AIFC import decode foundation`
22. Done: `sample: expose AIFF/AIFC through Sample Editor load workflow`
23. Done: `sample: add FLAC import decode foundation`
24. Done: `sample: expose FLAC through Sample Editor load workflow`
25. Done: `sample: add represented sample-slot lifecycle and Add as New Sample`
26. Done: `instrument: add editable keymap range foundation behind applyEdit`
27. Done: `instrument: wire selected-sample note-range assignment UI`
28. `sample: add editable loop mode and range behind applyEdit`

Save and Save As should remain disabled until the owned-path/native-format
decision is ready. Export XM can move first because it has clearer source
safety: it writes a user-chosen new interchange file and never mutates the
opened source module.

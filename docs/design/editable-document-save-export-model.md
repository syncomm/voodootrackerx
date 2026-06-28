# Editable Document Save/Export Model

Status: design-only. This note defines product and architecture rules for
future save/export work. It does not implement Save, Save As, Export XM, an XM
writer, loaded-module editing, Instrument Editor behavior, Sample Editor
behavior, runtime playback changes, parser architecture changes, or tracker
viewport changes.

## Purpose

VoodooTracker X now supports a first-pass composition workflow for blank
editable documents and loaded-module-derived clear-song copies. Before file
writing exists, the app needs explicit ownership rules so persistence cannot
overwrite a user's opened source module by accident.

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
| Blank editable document from `File > New` | Yes | In-memory document with no owned path | Save remains disabled until an owned document format/path exists. Export XM may later write a user-chosen new XM file. |
| Editable document derived from Clear Song Data or an editable-copy bridge | Yes | Value-owned copy of editable song/order/pattern state plus safely represented palette/sample data | The source module path, if any, remains external and read-only. Save/export must choose a new destination. |
| Loaded module read-only state | No | External opened module path owned by the user or filesystem, not by VTX | Pattern, song/order, instrument, and sample mutations are blocked. Save must not target this path implicitly. |
| Future explicit editable copy of a loaded module | Yes, after user command | New in-memory editable document derived from parsed module data | The original module remains untouched. The UI must show copied/read-only/owned state clearly. |
| Future saved/exported editable document state | Yes | User-chosen destination, with ownership made explicit | A native saved state requires a chosen native format/path. Exported XM is a public interchange artifact and should not silently become permission to overwrite an opened source module. |

Current `Edit > Clear Song Data` on a loaded module is an editable-copy bridge
with deliberately narrow semantics: it preserves safely represented
instrument/sample palette data and playable sample payloads where available,
then clears song/order/pattern note data into an editable blank song. It is not
full loaded-module editing.

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
- use generated public fixtures or synthetic editable documents for tests

The first writer does not need full XM feature coverage. It should produce a
valid public XM file for the editable subset that VTX currently understands.

First-writer limitations:

- no guarantee of round-trip parity with arbitrary loaded XM modules
- no full Instrument Editor state beyond fields currently represented by the
  editable document and playback/palette models
- no full Sample Editor or sample-import pipeline yet
- no private corpus dependency
- no generated XM/WAV artifacts committed outside explicit reviewed fixture PRs
- no broad parser/writer architecture rewrite
- no claim of FastTracker II, OpenMPT, or MikMod parity

## Loaded Module Editable-Copy Workflow

Future loaded-module editing must be explicit:

1. User opens a module. The loaded module remains read-only.
2. User chooses a command such as `Make Editable Copy` or
   `Save As Editable Copy...`.
3. VTX creates an editable in-memory copy of safely represented song/order,
   pattern, instrument, and sample data.
4. The UI communicates that the new document is a copy, not the source module.
5. Save/export writes only to a user-chosen destination.
6. The original opened source module remains untouched.

The copy workflow may preserve parsed instrument/sample palette data where the
current models can represent it safely. Data that VTX cannot yet represent
should be omitted or diagnosed rather than silently written back in a lossy
way.

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
- Instrument Editor or Sample Editor behavior

Export validation may later reuse existing offline/public-safe render tooling,
but save/export implementation should not add render behavior unless a focused
future PR explicitly scopes that work.

## Proposed Implementation Slices

Keep future PRs narrow and testable:

1. `app: define editable document save/export menu state`
2. `xm: add minimal public-safe XM writer model tests`
3. `xm: write editable blank document XM order/pattern/timing data`
4. `xm: write existing palette/sample payloads when available`
5. `app: wire Export XM save panel for editable documents`
6. `tests: add exported-XM reload smoke using public fixtures`
7. `app: define explicit loaded-module editable-copy command`
8. `instrument: build Instrument Editor shell/read-only binding`
9. `instrument: add editable palette foundation`
10. `sample: build Sample Editor shell/import foundation`

Save and Save As should remain disabled until the owned-path/native-format
decision is ready. Export XM can move first because it has clearer source
safety: it writes a user-chosen new interchange file and never mutates the
opened source module.

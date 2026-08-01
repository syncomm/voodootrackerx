# Agent Current State

Read this first when starting backend, audio, parser, effect, or tooling work.
It is the short current-state snapshot; load longer docs only when the task
needs them.

## Product Scope Pointer

VTX 1.0 is scoped as a self-contained XM-style sample/instrument tracker that
can create complete sample-based songs from scratch. It is not only a playback,
display, or pattern-entry milestone, and it is not a DAW/plugin-host milestone.

[ADR 012](decisions/012-from-scratch-instrument-sample-composition-model.md)
defines the File New-to-export instrument, sample, import, generation, keymap,
lifecycle, ownership, and release model. Its first implementation slice is now
present: File New owns one unnamed zero-sample I01 with an honest selected S01
destination, and `Edit > New Instrument` appends/selects another zero-sample
instrument through one labeled `applyEdit`/undo action. The command is limited
to stopped editable documents with capacity; loaded modules and playback remain
read-only. The current dense palette/writer model appends after the highest
represented slot and does not fill sparse holes. Sample Editor SINE now fills eligible
S01 with deterministic looped PCM and an all-note map. A UI-independent audio
import facade now validates container identity before dispatching WAV/WAVE,
AIFF/AIF, AIFC, or native `fLaC` to bounded decoders. Native FLAC is limited to
16/24-bit mono/stereo and uses raw STREAMINFO preflight plus chunked Apple
`ExtAudioFile` decode; 8-bit and all untested depths are rejected before decode.
Every format returns the same value-owned XM-representable 16-bit mono candidate.
Sample Editor LOAD uses that facade off the main thread: it fills empty S01 or offers
Replace/Add as New/Cancel for the exact represented selection, reuses stereo
Mix/Left/Right, and commits one import, replace, or append edit with stale-result
protection. Add appends/selects the next represented Sxx without changing the
keymap. Its panel accepts WAV/AIFF/AIFC and native FLAC; Ogg-FLAC is unsupported,
and FLAC metadata/loops are ignored. Instrument Editor now exposes non-mutating
inclusive range selection on its full 96-note summary plus explicit selected-sample
assignment; destructive lifecycle, drag-to-paint, and automatic mapping remain deferred.

Loaded modules remain read-only by default. Supported stopped loaded XM modules
can be converted only through the explicit `File > Make Editable Copy` command,
which creates an untitled in-memory editable copy without claiming the opened
source path.
Future plugin or audio-input bridges should start as later sample/import
experiments, not live plugin playback inside classic XM compatibility.

The post-v1 priority is VTX as an AUv3 tracker instrument before a general
Audio Unit host: native macOS AUv3 first, then iPadOS AUv3 after the headless
engine and contained UI are proven. AUv3 is the only approved format in this
direction; it does not expand v1, add a target, or change the runtime. See
`docs/decisions/011-post-v1-auv3-tracker-instrument-direction.md`.

Release status: `v0.2.0-alpha.5` is the released Rendered Audio Export Alpha.
Product whole-song 48 kHz Float32 WAV and AAC/M4A export is available from
`File > Export Audio` for stopped loaded modules, editable documents, and
editable copies. Export is non-mutating, writes only to the selected
destination, does not claim source-path ownership, keeps Save/Save As disabled,
does not use the diagnostic bounded-render cap, renders through the same
64-row windowed offline path used by the proven render tool mode, and applies
export-boundary auto-headroom without a second full mixer render. The app
product render default is 48 kHz Float32; M4A encodes the completed scaled PCM
as 192 kbps AAC for convenient sharing. Export can be cancelled cooperatively at
safe preparation, render-window, headroom-chunk, and final-write boundaries;
temporary output is removed, cancellation is non-mutating, and determinate
progress is continuous and weighted across the remaining phases. WAV remains
the preferred high-quality and export-diagnostic format; M4A is intended for
convenient sharing. Export XM remains scoped to the current editable subset,
not an arbitrary-XM round-trip guarantee or full FT2/OpenMPT/MilkyTracker
parity claim. `Window > Instrument Editor` follows the v1 mockup hierarchy for
the current palette selection, represented sample metadata, read-only VOL/PAN envelope
preview, and note-map ranges. Represented instrument NAME plus selected-sample
PAN, VOLUME, REL NOTE, and FINETUNE are editable only in stopped editable documents or
editable copies; all use labeled whole-document `applyEdit` undo/redo. Sample panning is the first
editable sample metadata field and preserves the exact XM `0...255` byte
through snapshots and Export XM. Loaded modules, playing documents, missing or
empty sample slots, and all unimplemented mutation controls remain read-only/inert.
Represented instrument/sample rows share the main control-panel selection in loaded or editable
documents, including during playback. Row selection is non-mutating, creates no undo, cancels stale
preview before switching context, and drives metadata and the next audition; transport gates mutation only.
The floating Instrument Editor closes through its red close button or Command-W without
closing the main app window, and `Window > Instrument Editor` recreates one clean
controller/router afterward. Its computer-key audition router inspects only keyDown/keyUp events;
the local on-screen keyboard handles only primary-pointer presses on its rendered keys. Editable-copy feedback
remains a document-level sheet on the main tracker window; when invoked from the key Instrument
Editor, that floating panel is temporarily ordered behind the sheet and restored after dismissal.
Open/reopen starts on the non-editing content responder rather than selecting NAME; NAME
enters normal AppKit text editing only after explicit focus, temporarily suppressing audition.
When the Instrument Editor is the key window, unmodified tracker note keys outside text
responders use the shared note map, current octave/selection, availability resolver, and
preview sink. This window-scoped path is audition-only and its active preview is not transport
playback: supported controls remain editable while previewing, edits apply to the next trigger,
and closing the window cancels its preview and detaches its handlers. The on-screen keyboard keeps a
three-octave window that defaults to C-2...B-4 and shifts by octave across the 96-note map without
document or undo mutation. Focused computer-key and mouse audition share one generation-token
pressed visual when the active note is visible; both remain monophonic. Dragging crosses with
release/press semantics.
Mouse-up, outside drag, selection/document transitions, deactivation, and close clear its voice and pressed state. XM note maps select the clicked note's sample without changing editor selection.
Loaded modules stay read-only; audition creates no document or undo mutation.
`Window > Sample Editor` now opens one active fixed utility window at a time,
aligned to
`assets/mockups/sample-editor-v1.html`, which is authoritative over prose for
visual hierarchy and geometry. It shares the canonical instrument/sample
selection with the main control panel and Instrument Editor. Its compact
instrument popup changes that shared UI state without document mutation or undo,
reuses the canonical sample-normalization policy, and stays selectable for
loaded/editable documents during playback. The selected sample row, header,
exact metadata, bounded read-only min/max waveform, and display-only
no/forward/ping-pong loop region now derive from one represented sample.
Unnamed represented samples show `(unnamed sample)`; absent samples clear every
sample surface. FORMAT reports represented bit depth and mono without treating
playback-policy `baseSampleRate` as source metadata.
SINE and audio LOAD are the current Sample Editor mutations. LOAD is available
only for a stopped editable empty S01 or represented selected sample and is
disabled during an active import. Its single-file panel accepts WAV/WAVE,
AIFF/AIF, AIFC, and native FLAC; container identity is authoritative and
recognized extension/container mismatches are rejected. Native FLAC accepts
only mono/stereo 16-bit and 24-bit sources. It rejects 8-bit and untested
depths, Ogg-FLAC, invalid STREAMINFO, unsafe dimensions, and decoder/preflight
disagreement; metadata and loops are ignored. Mono skips channel choice, while
stereo offers Mix/Left/Right. Decode/normalization runs in the background with
exact document identity/revision/selection/occupancy revalidation. One `Import
Audio Sample` or `Replace Audio Sample` edit owns canonical mono 16-bit PCM;
empty import establishes the all-S01 map, while replacement preserves the
exact slot, keymap, and unrelated instrument data. Commit cancels stale preview
once, refreshes every editor, and does not auto-audition; the next trigger uses
imported PCM, pan, gain, and tuning. Undo/redo restores exact prior/imported
state, and no source path is retained. Destructive sample lifecycle remains deferred.
Separately, stopped editable documents can map a nonempty represented sample in
the selected instrument through the Instrument Editor's `MAP RANGE…` sheet over
the canonical C-0...B-7 domain. A transient range dragged on the full-map summary
is the first sheet default, followed by a focused note, selected octave, then C-4...B-4.
One `Map Sample to Note Range` edit preserves selection and notes outside the
range; failures and no-ops create no revision/history, and undo/redo is exact.
Instrument Editor/pattern playback consume the map while Sample Editor audition
stays direct-selected-sample. There is no automatic/drag mapping or auto-audition.
Sample Editor AUDITION now toggles the represented selected slot directly at
C-4 through the persistent preview stream for loaded/read-only and editable
sources, preserving existing PCM/loop/volume/pan/tuning planning without keymap
lookup or mutation. Instrument Editor remains keymap-driven. Note selection and
natural-completion UI notification remain future work; no polling is used.
Selected-sample volume now likewise preserves exact XM `0...64` values through
`applyEdit`, undo/redo, and Export XM; subsequent playback uses the existing
adapter gain mapping without runtime engine, DSP, or scheduling changes.
Selected-sample relative note preserves the exact XM signed byte `-128...127`
through the same paths; later playback uses the existing pitch adaptation.
Selected-sample finetune preserves the exact XM signed byte `-128...127` through
the same paths; later playback uses the existing pitch adaptation with no pitch
formula, runtime engine, DSP, or scheduling architecture change.
PAN, VOLUME, and FINETUNE numeric and accessibility values now update transiently
during drag. Intermediate values do not mutate the document or preview voice;
mouse-up creates at most one existing labeled `applyEdit` undo action, lifecycle
cancellation restores canonical state, and the persistent preview stream is unchanged.
Sample-header panning now initializes preview, runtime, and product-export
voices from the resolved sample. Its monotonic mapping is exact at byte `0`
(`-1`), `128` (`0`), and `255` (`+1`); existing volume/effect panning then
keeps its established mapping and precedence. Edits affect the next trigger,
not a held voice, with no backend or C mixer DSP change. XM instrument
autovibrato type/sweep/depth/rate bytes are likewise preserved through editable
copy, snapshots, and Export XM, shown on disabled VIBRATO controls, and remain
runtime/audition-inert. XM instrument panning-envelope points, counts, sustain/
loop indices, and supported flags are now preserved through the same loaded,
editable-copy, snapshot, and Export XM paths. The local display-only VOL/PAN
selector exposes their graph, point count, enabled, sustain, and loop state;
they remain runtime-inert and create no document or undo mutation. These
metadata slices add no loop, PCM, envelope, waveform, vibrato, or XI mutation.
Save/Save As,
loaded-module direct editing, broader Instrument Editor editing, Sample Editor mutation beyond SINE/audio LOAD, PCM16 product export,
pattern/order ranges, channel/stem export, diagnostic comparison
profile UI, and user-selectable gain/headroom remain future work.

The public synthetic XM corpus now includes deterministic sustained 16-bit,
five-instrument metadata-matrix, and two-sample envelopes/keymap fixtures. A schema-v2 reviewable
manifest pins PCM/XM hashes and byte counts; the existing generator validates,
generates one or all approved fixtures, and verifies committed bytes without
rewriting. Tests cover the C loader, playback model, editable-copy, current
metadata edits/undo/redo, 8/16-bit PCM, no/forward/ping-pong loops,
exact panning preservation/planning, and Export XM/reopen. The three-part
instrument fixture series is complete. The pack is original MIT-licensed project data and adds no
XI, imported audio, runtime, parser, writer, mixer, DSP, scheduling, or UI
behavior.

## Backend Architecture

- Runtime playback defaults to the CoreAudio DefaultOutput Audio Unit host
  driving the C mixer render core.
- `VTX_AUDIO_BACKEND=c_mixer` and `VTX_AUDIO_BACKEND=c_mixer_coreaudio` are
  explicit aliases for the same CoreAudio C mixer path.
- `VTX_AUDIO_BACKEND=av_audio` is retired. It must not be reintroduced as a
  runtime backend; it falls back to the CoreAudio C mixer and reports a
  diagnostic fallback reason.
- The retired AVAudioPlayerNode / AVAudioUnitVarispeed path and the retired
  AVAudioSourceNode C mixer host must not return.
- The Swift playback/adapter layer plans module events; the C mixer owns the
  render core used by runtime playback and bounded offline renders.
- Offline render/export remains the reference workflow for deterministic audio
  comparison. Runtime smoke checks validate the app host path and delivery.
- Product WAV export uses the existing bounded offline C mixer render path with
  VTX mix profile, whole-song 48 kHz Float32 WAV output, explicit
  user-initiated long-render planning, 64-row windowed scheduling, and
  export-boundary auto-headroom. The app path renders the mixer once, records
  peak diagnostics while writing an unscaled Float32 temp WAV, then applies the
  shared auto-headroom gain through a streamed Float32 WAV post-process; it
  does not change runtime playback, scheduling, or C mixer DSP.
- Product M4A export reuses the same WAV plan and completed scaled Float32 temp
  output, then encodes fixed 192 kbps AAC through AVFoundation. The encoder is
  an app-level boundary and does not change WAV output, render PCM, runtime
  playback, scheduling, or C mixer DSP.
- `CSoftwareMixer` owns the large `VTXCMixerState` on the heap so background
  offline export/render workers do not initialize that fixed-size C state on a
  smaller GCD worker stack.

## Current Runtime Default

Unset `VTX_AUDIO_BACKEND` means CoreAudio C mixer. Unknown backend names fall
back to that default and should remain diagnostics, not alternate behavior.

Runtime-only diagnostics may use:

- `VTX_C_MIXER_RUNTIME_TRACE_PATH` for local JSONL trace output.
- `VTX_C_MIXER_RUNTIME_CAPTURE_PATH` for local runtime CoreAudio capture.
- `VTX_RUNTIME_MIXER_METRICS_TRACE` for sanitized runtime mixer stop summaries.
- `VTX_DEBUG_AUTOPLAY` and `VTX_DEBUG_STOP_AFTER_SECONDS` for bounded manual
  smoke runs.

Generated traces, captures, logs, reports, screenshots, and listening notes
stay under `/tmp` or another untracked local path.

Xcode 16.4 CI has crashed the Swift frontend when new diagnostics were wired
through compiler-sensitive default `PlaybackEngine()` stored-property
initialization from `AppDelegate`. For diagnostic PRs, keep new recorder/sink
objects disabled by default and prefer explicit AppDelegate/factory injection
or small value types over adding diagnostic object creation to PlaybackEngine
default initializer paths. Treat the macOS CI Xcode build as the verification
gate even when local SwiftPM and newer local Xcode builds pass.

## Offline Render / Export Workflow

Use `swift run -c release vtx_render_bounded_xm` for local candidate renders.
Plain `swift run` builds Debug by default and is not valid for render/export
performance comparisons. The render tool loads XM through the repo
parser/builders and renders through the bounded offline C mixer path.

For product-comparable local render timing, prefer `./scripts/bench-render.sh`.
Generated WAVs, diagnostics, reports, and timing notes stay under `/tmp` or
another ignored local path.

For FT2-style reference comparisons, prefer:

```bash
LOCAL_XM="path-to-untracked-local-module.xm"

swift run -c release vtx_render_bounded_xm \
  --input "$LOCAL_XM" \
  --output /tmp/vtx-ft2-profile-candidate.wav \
  --diagnostics-json /tmp/vtx-ft2-profile-diagnostics.json \
  --sample-rate 48000 \
  --until-song-end \
  --tail-seconds 3 \
  --window-rows 64 \
  --allow-long-render \
  --wav-format float32 \
  --mix-profile ft2
```

Use `--mix-profile vtx` when you are validating the project default export
policy. Use `--mix-profile ft2` when comparing against the ft2-clone Linear
reference policy.

Use `--wav-format float32` for reference comparison and overrange/headroom
diagnostics. Use default PCM16 only for quick listening smoke checks or when a
target tool requires PCM.

## ft2-clone Reference Policy

ft2-clone Linear is the primary FT2-style XM reference when a matching local
export is available. Record the local reference settings in any local report:

- sample rate
- Float32 or PCM export format
- Linear interpolation
- Linear frequency slides
- amplification and master volume
- volume ramping setting
- precise BPM setting
- whether stems or individual tracks were exported

MikMod, OpenMPT/libopenmpt, Renoise, and other tools can be useful secondary
references, but reference correlation alone is not a correctness proof.

## Runtime / Offline Equivalence

For tested modules, runtime CoreAudio capture and offline C mixer render have
been shown equivalent at the render-core/output-capture level. Treat new
runtime/offline mismatch evidence as a diagnostic task: confirm capture bounds,
sample rate, gain/headroom, trace health, and comparison settings before
proposing playback behavior changes.

## Private Corpus Rules

- Do not commit private modules or artifacts derived from them.
- Do not publish private filenames, local absolute paths, or machine-specific
  notes.
- Use anonymized labels only when examples are necessary.
- Keep local label maps outside the repository.
- Put local/private reports under `/tmp` unless the maintainer explicitly asks
  for a public-safe committed report.

## Effect Support Pointer

`docs/xm-effect-support.md` is the canonical current effect support table.
Read it before effect work and update it when an effect PR changes support.
It uses Implemented / Implemented, parity-watch / Deferred terminology to
separate current VTX support from tracked parity gaps and unimplemented
commands.

## Diagnostic Tooling Pointer

For diagnostic script inventory and consolidation planning, see
`docs/diagnostic-tools.md`.

## Backend Freeze Posture

The XM backend is under a temporary foundation freeze. Do not promote
behavior-changing effect, C mixer DSP, parser architecture, runtime backend, or
tracker viewport work by default.

Backend PRs should be promoted only for release-blocking crashes,
deterministic runtime/offline mismatches, severe open-time/performance
regressions, or maintainer-promoted compatibility blockers.

Parked parity-watch items:

- Broader Amiga-table follow-up for the remaining late looped-sample phase
  residual; use reference-stem/per-voice diagnostics before changing VTX loop,
  ramp, timing, or sample-step behavior.
- `R00` memory refinement as a later parity-watch cleanup unless the maintainer
  promotes it under a freeze-exit criterion.

Recently completed narrow targets:

- The deterministic public XM reference pack now has its sustained foundation,
  five-instrument metadata matrix, and two-sample envelopes/keymap fixture,
  backed by a schema-v2 source manifest,
  pinned PCM/XM hashes, byte-identical regeneration, loader/model/editable-copy/
  current-edit/Export XM round trips, and tracked-file hygiene. The pack pins
  panning, volume, signed tuning, 8/16-bit PCM, all XM loop modes, split note
  mapping, both envelope headers, fadeout, and autovibrato. Production playback
  and format code are unchanged; named empty/sample-less cases remain deferred.
- The selected represented sample's exact XM signed relative-note and finetune
  bytes (`-128...127`) now edit only in stopped editable documents/copies through
  labeled `applyEdit` actions with undo/redo. Export XM/reopen preserves each
  exact byte, and subsequent playback uses the existing pitch/sample-step adaptation;
  pitch formulas, scheduling, runtime engine behavior, C mixer DSP, and all
  neighboring sample/instrument data are unchanged.
- The selected represented sample's exact XM panning byte is the first editable
  sample metadata field. Its Instrument Editor PAN control is enabled only for
  stopped editable documents/copies, commits one `Change Sample Panning`
  `applyEdit` action with undo/redo, and remains disabled for loaded modules,
  playback, or empty slots. Export XM/reopen preserves the edited byte while
  adapter plans, voice pan, render PCM, and audition remain unchanged.
  `PlaybackInstrumentAutoVibrato` provides
  same exact preservation for the four XM autovibrato bytes and read-only
  VIBRATO display. `PlaybackPanningEnvelope` preserves up to 12 XM panning-
  envelope points plus count, sustain/loop indices, and supported type flags
  through the same value paths and writer; the Instrument Editor displays them
  read-only through its local VOL/PAN selector. Playback/audition behavior, scheduling, render PCM, C
  mixer DSP, parser architecture, and loaded-module read-only rules are
  unchanged.
- `EditableDocumentEditCoordinator` now applies labeled whole-document value
  snapshots with a 20-level `UndoManager`, refreshes the existing tracker,
  control-panel, Song / Order, and Instrument Editor state paths, and rejects
  loaded read-only or playback-active contexts. Clear Current Pattern proves
  undo/redo; source paths are absent from the edit context, Save/Save As stay
  disabled, and broader instrument/sample editing remains future work.
- `Window > Instrument Editor` now opens one reusable fixed 920 × 638 utility
  window aligned to `assets/mockups/instrument-editor-v1.html`, bound to the current document and selection.
  Supported stopped-editable metadata routes through undo, and computer/graphical keys use isolated preview.
  Its explicit selected-sample range sheet wires the existing one-edit keymap
  foundation; XI, envelope editing, graphical mapping, and waveform controls
  stay disabled. Loaded modules stay read-only,
  and no parser, runtime transport, or broad writer/export behavior changed.
- `File > Export Audio > M4A...` now reuses the stopped product WAV plan and
  scaled Float32 temp output for loaded modules, editable documents, and
  editable copies, then encodes fixed 192 kbps AAC through a narrow
  AVFoundation boundary. It writes only to the selected `.m4a` destination,
  reports render/headroom/encoding/write progress, cancels cooperatively,
  cleans temporary/partial output, leaves documents and source ownership
  untouched, and keeps Save/Save As plus loaded-module editing disabled. WAV
  output, render PCM, runtime playback/scheduling, C mixer DSP, parser,
  tracker viewport, and XM writer behavior are unchanged.
- `File > Export Audio > WAV...` now renders the current stopped loaded module,
  editable document, or editable copy to a user-selected 32-bit Float WAV via
  the existing bounded offline C mixer path. The app uses the VTX mix profile,
  an explicit user-initiated whole-song long-render policy, default song-end
  tail, 48 kHz output, 64-row windowed scheduling, and export-boundary
  auto-headroom instead of the diagnostic bounded-render cap. It performs one
  expensive mixer render, writes an unscaled Float32 temp WAV while computing
  peak diagnostics, applies the shared auto-headroom gain through a streamed
  Float32 WAV post-process, keeps preparation/indexing indeterminate, then
  shows continuous weighted whole-export progress across rendering, headroom,
  and final writing while rendering on a background queue,
  writes through temporary files before replacing the selected destination,
  supports cooperative cancellation at safe phase boundaries, removes
  temporary output on cancellation or failure, leaves source modules/documents
  untouched, does not claim source-path ownership, keeps Save/Save As disabled,
  and leaves loaded modules read-only. PCM16, pattern or order ranges,
  channel/stem export, normalization,
  diagnostic comparison profiles, and user-selectable gain/headroom remain
  future work.
- `File > Make Editable Copy` now defines the explicit loaded-module editable
  copy boundary. It is available only for stopped loaded read-only XM modules
  that can be represented by the current editable subset, creates an untitled
  in-memory editable copy of supported song/order/pattern/note data plus
  represented palette/sample payloads, leaves the source module read-only and
  untouched, does not claim source-path ownership, keeps Save/Save As disabled,
  and allows stopped Export XM to a user-selected destination. Runtime
  playback/scheduling, `RuntimeCMixerAdapterEventPlan`, C mixer DSP, parser
  architecture, and tracker viewport/static-highlight behavior did not change.
- Export XM v1 release-prep documentation for `v0.2.0-alpha.4` now states the
  scoped release claim, manual smoke checklist, and maintainer-only post-merge
  tag instructions. No tag should be created by the PR.
- XM diagnostic and residual-scan recommendation wording aligned with the
  backend freeze and `docs/xm-effect-support.md`; no playback behavior changed.
- Amiga frequency-table foundation for note period/frequency/sample-step
  calculation, sample finetune metadata, Amiga-table `2xx` portamento down,
  and effect-column `3xx` tone portamento in the shared runtime/offline C
  mixer adapter path.
- `Lxx` set envelope position foundation.
- Volume-column `F0...FF` tone portamento foundation.
- Final expanded-corpus linear-XM effect coverage before Amiga; no deferred
  linear command was promoted ahead of Amiga frequency-table work.

Retired AVAudio backend cleanup belongs to docs/tooling or deletion tasks only;
do not reintroduce retired playback paths.

## Required Verification Command Groups

For docs/tooling hygiene PRs:

```bash
./scripts/check-files.sh
git diff --check
```

Also run the private-name/local-path scan requested by the task or PR checklist.
Do not copy private names or local absolute path patterns into committed docs.

For effect/backend behavior PRs, also run focused Swift tests for the touched
adapter/mixer area and update `docs/xm-effect-support.md` when support changes.

For tracker viewport work, use the tracker UI docs and manual screenshot
verification. Do not treat backend docs as viewport guidance.

## Long-Doc Loading Rules

- Read `docs/audio-comparison.md` only for render/reference comparison work.
- Read `docs/playback-trace.md` only for runtime trace or diagnostic work.
- Read `docs/roadmap.md` for current milestone sequencing.
- Read `docs/dev-roadmap.md` for the short phase summary.
- Read reports under `docs/reports/` only when investigating that historical
  thread.

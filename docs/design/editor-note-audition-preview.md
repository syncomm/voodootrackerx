# Editor Note Audition Preview Plan

This note defines the editor-side request shape and input policy for note audition preview. The current implementation supports isolated represented-sample audition from tracker note keys in both the tracker and focused Instrument Editor, plus its octave-shiftable three-octave on-screen keyboard, when real sample payload is available. Focused computer and mouse audition share the active generation token and one visible pressed-key treatment; range changes only change whether that sounding monophonic note is visible. Runtime song playback, transport state, backend selection, parser architecture, tracker viewport behavior, loaded-module pattern mutability, keymap assignment, and runtime-inert sample-header panning remain unchanged.

## Request Meaning

When the tracker note field receives a tracker note key, the editor may create an `EditorNoteAuditionRequest`. The request is preview-only data: note value, selected octave, selected 1-based instrument/sample slots, source context, and optional row/channel context. Edit-mode pattern mutation is a separate policy decision from preview routing.

The current audible sink maps the typed note value to preview playback pitch using the existing runtime pitch calculator and the resolved sample's base rate, relative note, and finetune metadata. Lower-row tracker keys preview at the selected octave, and upper-row tracker keys preview at selected octave + 1, matching note-entry routing. The same preview-only mixer wrapper used by the CoreAudio sink receives that computed playback step, so tests cover the scheduling path that audible preview uses. The preview sink applies sample volume through the same loaded-module adapter gain helper used by runtime playback at neutral channel/global volume, applies the default runtime C mixer output headroom gain, and then bounds the result with a preview-only safety cap above the normal default-runtime preview level. This is a preview boundary policy only: it does not change runtime song playback gain, module/runtime gain configuration, global volume, channel volume, volume-column state, or envelope state. Repeated AppKit keyDown events for tracker note keys do not retrigger preview, so a held key produces only the initial audition; if the resolved sample carries supported loop metadata, the preview voice may sustain through that loop until key release cancels it.

Graphical presses create the same request with the exact rendered-key pitch. A 96-note XM map resolves the mapped sample without changing selection; otherwise selected-sample routing remains.

Tracker note key release is preview-only in both Edit and non-Edit modes. A previewable tracker note `keyDown` starts or replaces the active preview note, and the matching tracker note `keyUp` stops/cancels only the active editor preview voice through the isolated preview sink. Key release does not write pattern data and never inserts `===`. Pattern key-off remains the explicit `===` note entry through the backtick/grave-accent key binding only where editing is allowed.

## Source Rules

Blank documents currently contain selected instrument/sample slots such as `I01`/`S01`, but no real instrument or sample payload. They are therefore preview-unavailable until a later milestone adds a real playable payload through import, sample loading, or editors.

Loaded modules may be auditionable before they become editable. Loaded-module audition resolves selected instrument/sample data from the loaded playback model, but it must not mutate loaded pattern data.

## Loaded-Module Sample Availability

Loaded-module preview availability resolves the editor note-audition request against the app-level `PlaybackSong` instrument/sample model. A selected instrument/sample is unavailable when the loaded playback song is missing, the selected instrument cannot resolve, the selected sample slot cannot resolve on that instrument, or the selected sample has no playable PCM payload. A resolved sample with payload reports a descriptor containing the instrument index, sample index, frame count, sanitized forward or ping-pong sample-loop metadata when present, source context, and a copied preview PCM payload.

Computer-key loaded XM preview uses the editor's loaded-module instrument and sample-slot selection state instead of hard-coding `I01`/`S01` or following the runtime song adapter's note sample-map / first-playable fallback. Main popups and Instrument Editor rows update that same canonical selection in loaded/editable and stopped/playing states without document mutation or undo; a change cancels stale preview before switching context. Graphical-keyboard preview deliberately uses the selected instrument's XM note map for the clicked pitch without changing that selected sample slot. Keymap assignment remains read-only while graphical keys remain auditionable.

Preview availability resolves the selected 1-based sample slot directly to the selected instrument's stored 0-based sample index. An unavailable selected sample slot, missing slot, empty PCM payload, or otherwise non-playable selected sample returns preview-unavailable. The resolver does not silently fall back to `S01` or to the first playable sample for editor audition.

This resolver does not play audio, schedule voices, call CoreAudio, or change playback transport behavior. Loaded modules may be previewable before they become editable. Blank documents remain preview-unavailable until they have real instrument/sample payload through later import or editor support.

Positive loaded-module preview availability is covered by the generated public
XM fixture `tests/reference-xm/generated/basic-instrument-sample.xm`, loaded
through the normal public fixture path and `PlaybackSongBuilder`. The tests
prove selected `I01` / `S01` resolves to a real one-sample PCM payload and a
preview descriptor with copied PCM, volume, parsed base sample rate, relative
note, finetune metadata, and no loop metadata. Synthetic unit tests cover
forward and ping-pong loop descriptor routing until a public looped XM fixture
is added. The generated fixture continues to assert the expected parsed base
sample rate of 8,363 Hz. Loaded modules remain read-only.

## Input Routing Policy

`EditorNoteAuditionInputPolicy` is the explicit note-field routing policy:

- Edit mode ON plus blank-document source may mutate note-field pattern data.
- Edit mode OFF never mutates pattern data.
- Loaded-module sources never mutate pattern data, regardless of Edit mode.
- Tracker note-key `keyDown` may request preview in both Edit and non-Edit modes.
- Non-Edit-mode note-key `keyDown` may audition the selected loaded-module instrument/sample when availability resolves to a previewable payload.
- Blank documents remain preview-unavailable because selected `I01` / `S01` slots do not contain real instrument/sample payload.
- Repeated loaded-module note-key `keyDown` events are consumed without retriggering preview.
- Backtick remains explicit pattern key-off entry only when editing is allowed.
- Delete/Backspace and `.` clear note data only when editing is allowed.
- Tracker note-key `keyUp` stops/cancels the matching active preview in both Edit and non-Edit modes.
- Tracker note-key `keyUp` does not write pattern data and never inserts `===`.
- The Instrument Editor uses a window-scoped responder path only while it is key;
  text responders, modified shortcuts, navigation, and menu commands win.
- Open/reopen starts with the non-editing content responder, so audition is immediately eligible;
  NAME uses the normal field editor only after explicit focus and suppresses audition until focus leaves.
- Instrument Editor audition reuses the current octave/selection and availability/preview pipeline,
  and never mutates patterns, cursor/edit-step state, undo history, or document data.
- Primary presses use black-key overlap precedence; same-key drag does not retrigger, while key crossings emit release then press.
- Outside drag, mouse-up, selection/document transition, deactivation, and close clear the note/visual; rejected or secondary presses create no state.

Spacebar Play/Stop remains transport routing before edit input. Note audition does not call `PlaybackEngine`, does not toggle transport state, does not start runtime song playback, and does not move playback-follow or row-follow position.

An active Instrument Editor preview is therefore not transport playback and does not disable
otherwise eligible NAME, PAN, VOLUME, FINETUNE, or REL NOTE controls. Volume, finetune, and relative
note edits are resolved from current document/selection state on the next trigger through the existing
gain and pitch mappings; no held-note modulation or automatic retrigger is implied. Sample-header
panning remains editable/exportable but intentionally absent from preview/runtime pan. Closing the
Instrument Editor cancels any computer or graphical preview and detaches its window-local handlers before the
presenter releases the controller; reopening installs one fresh router without a global event monitor.

## First Preview Spike

The first routing spike added `EditorNoteAuditionPreviewer`, which consumes an `EditorNoteAuditionRequest` plus an `EditorNoteAuditionAvailability` result. It attempts preview only for note-on requests whose descriptor comes from a loaded module and reports real sample payload with a positive frame count and copied PCM payload. The previewer uses an injected sink so tests can verify request routing and metadata without CoreAudio or audio hardware.

The audible spike adds `EditorNoteAuditionAudioSink` behind the existing `EditorNoteAuditionPreviewSink` boundary. The sink owns a separate preview-only CoreAudio DefaultOutput unit and a separate `CSoftwareMixer` instance. It does not call `PlaybackEngine`, does not call runtime `PlaybackAudioOutput.trigger(_:)`, does not start or stop song transport, does not publish playback-follow positions, does not alter Play/Stop button state, and does not participate in offline render/export behavior.

Each new preview note replaces the prior editor preview voice. The preview mixer explicitly clears loaded preview voices before scheduling the new one; this avoids layering stale one-shot voices while keeping full FT2/XM release-envelope behavior deferred.
The editor previewer tracks the active preview key identity with a generation token. Releasing the matching key stops the active preview through the preview-local cancel path. Releasing an older key after a newer note preview has replaced it is ignored, so stale keyUp events do not cancel the newer audition.

The current audible preview is intentionally simple:

- loaded-module note-on requests only
- tracker note-field note input in Edit and non-Edit modes
- exact-pitch Instrument Editor graphical-keyboard input with mouse drag transitions
- selected instrument/sample must resolve to `.potentiallyAvailable(...)`
- repeated note-key `keyDown` events do not retrigger preview
- copied Float32 mono PCM payload must be non-empty
- one-shot C mixer voice for non-looping samples
- forward and ping-pong sample-loop metadata can sustain the held preview voice
  through the existing preview-only `CSoftwareMixer` wrapper
- playback step maps typed note/octave through `PlaybackPitchCalculator`
- each new preview clears the previous preview voice before scheduling the replacement
- matching tracker note `keyUp` or graphical release immediately cancels the active preview voice only
- keyUp does not write pattern `===`; backtick remains the explicit pattern key-off
- preview gain uses loaded-module adapter sample gain at neutral channel/global volume, default runtime output headroom, and a final preview-only safety cap
- no full gain/loudness parity with normal Play/song playback yet
- no envelope processing
- no XM effect processing
- no pattern timing
- no full FT2/XM key-off envelope or fadeout release parity

Looped sample preview sustain is limited to sample-loop metadata already exposed by the loaded playback model and accepted by the preview-only mixer wrapper. Full FT2/XM envelope, key-off, fadeout, and effect parity remains deferred.

Preview is not attempted for blank documents without real sample payload, key-off requests, clear/delete input, navigation, unsupported keys, unavailable selected instrument/sample state, or loaded-module samples without previewable PCM payload. Loaded modules remain read-only for pattern mutation, even when their sample descriptors are potentially previewable. Blank documents remain silent and preview-unavailable until sample import/loading/editor support provides real payload. Play/Stop transport, transport state, and normal song playback remain unrelated to editor preview and unchanged by this preview sink.

## Deferred Work

- A separately scoped compatibility/design task for audible sample-header panning in playback and audition.
- Full preview gain/loudness parity with normal Play/song playback, including global volume, channel volume, volume-column state, envelopes, and effect-derived gain changes.
- Full FT2/XM release, key-off envelope, fadeout, envelope, effect, and loop parity beyond simple sample-loop sustain.
- XI import, sample loading, instrument editor, sample editor, and save/export behavior.
- Pattern loop while editing.
- Instrument entry, sample entry, effect entry, volume-column entry, and save/export behavior.
- Transport-coupled preview controls.

# Editor Note Audition Preview Plan

This note defines the editor-side request shape for note audition preview. The current spike proves an isolated loaded-module sample audition path for Edit-mode note input with real public fixture sample payload, while keeping runtime song playback, transport state, backend selection, parser architecture, tracker viewport behavior, and loaded-module pattern mutability unchanged.

## Request Meaning

When Edit mode receives a tracker note key, the editor may create an `EditorNoteAuditionRequest` alongside the existing pattern note-entry action. The request is preview-only data: note value, selected octave, selected 1-based instrument/sample slots, source context, and optional row/channel context.

The current audible sink maps the typed note value to preview playback pitch using the existing runtime pitch calculator and the resolved sample's base rate, relative note, and finetune metadata. Lower-row tracker keys preview at the selected octave, and upper-row tracker keys preview at selected octave + 1, matching note-entry routing. The same preview-only mixer wrapper used by the CoreAudio sink receives that computed playback step, so tests cover the scheduling path that audible preview uses. The preview sink applies sample volume through the same loaded-module adapter gain helper used by runtime playback at neutral channel/global volume, applies the default runtime C mixer output headroom gain, and then bounds the result with a preview-only safety cap above the normal default-runtime preview level. This is a preview boundary policy only: it does not change runtime song playback gain, module/runtime gain configuration, global volume, channel volume, volume-column state, or envelope state. Non-Edit-mode keyboard audition is deferred. Repeated AppKit keyDown events for tracker note keys do not retrigger preview, so a held key produces only the initial one-shot audition.

Edit-mode note key release is preview-only. A previewable tracker note `keyDown` starts or replaces the active preview note, and the matching tracker note `keyUp` stops/cancels only the active editor preview voice through the isolated preview sink. Key release does not write pattern data and never inserts `===`. Pattern key-off remains the explicit `===` note entry through the backtick/grave-accent key binding.

## Source Rules

Blank documents currently contain selected instrument/sample slots such as `I01`/`S01`, but no real instrument or sample payload. They are therefore preview-unavailable until a later milestone adds a real playable payload through import, sample loading, or editors.

Loaded modules may become auditionable before they become editable. Future loaded-module audition may resolve selected instrument/sample data from the loaded playback model, but it must not mutate loaded pattern data.

## Loaded-Module Sample Availability

Loaded-module preview availability resolves the editor note-audition request against the app-level `PlaybackSong` instrument/sample model. A selected instrument/sample is unavailable when the loaded playback song is missing, the selected instrument cannot resolve, the selected instrument's runtime sample-selection policy cannot resolve a playable sample, or the resolved sample has no playable PCM payload. A resolved sample with payload reports a descriptor containing the instrument index, sample index, frame count, loop metadata presence, source context, and a copied preview PCM payload.

Loaded XM preview now uses the editor's loaded-module instrument selection state instead of hard-coding `I01`/`S01`. The existing instrument popup can update the selected instrument for preview. The sample popup is still a sample-map placeholder, so loaded-module preview follows the selected instrument's note sample map, or the same first-playable fallback used by the current playback adapter, until a later sample/instrument selection milestone makes sample slots user-addressable.

This resolver does not play audio, schedule voices, call CoreAudio, or change playback transport behavior. Loaded modules may be previewable before they become editable. Blank documents remain preview-unavailable until they have real instrument/sample payload through later import or editor support.

Positive loaded-module preview availability is covered by the generated public
XM fixture `tests/reference-xm/generated/basic-instrument-sample.xm`, loaded
through the normal public fixture path and `PlaybackSongBuilder`. The tests
prove selected `I01` / `S01` resolves to a real one-sample PCM payload and a
preview descriptor with copied PCM, volume, parsed base sample rate, relative
note, and finetune metadata. The generated fixture continues to assert the
expected parsed base sample rate of 8,363 Hz. Loaded modules remain read-only.

## First Preview Spike

The first routing spike added `EditorNoteAuditionPreviewer`, which consumes an `EditorNoteAuditionRequest` plus an `EditorNoteAuditionAvailability` result. It attempts preview only for note-on requests whose descriptor comes from a loaded module and reports real sample payload with a positive frame count and copied PCM payload. The previewer uses an injected sink so tests can verify request routing and metadata without CoreAudio or audio hardware.

The audible spike adds `EditorNoteAuditionAudioSink` behind the existing `EditorNoteAuditionPreviewSink` boundary. The sink owns a separate preview-only CoreAudio DefaultOutput unit and a separate `CSoftwareMixer` instance. It does not call `PlaybackEngine`, does not call runtime `PlaybackAudioOutput.trigger(_:)`, does not start or stop song transport, does not publish playback-follow positions, does not alter Play/Stop button state, and does not participate in offline render/export behavior.

Each new preview note replaces the prior editor preview voice. The preview mixer explicitly clears loaded preview voices before scheduling the new one; this avoids layering stale one-shot voices while keeping full FT2/XM release-envelope behavior deferred.
The editor previewer tracks the active preview key identity with a generation token. Releasing the matching key stops the active preview through the preview-local cancel path. Releasing an older key after a newer note preview has replaced it is ignored, so stale keyUp events do not cancel the newer audition.

The current audible preview is intentionally simple:

- loaded-module note-on requests only
- Edit-mode note input only
- selected instrument/sample must resolve to `.potentiallyAvailable(...)`
- repeated note-key `keyDown` events do not retrigger preview
- copied Float32 mono PCM payload must be non-empty
- one-shot C mixer voice
- playback step maps typed note/octave through `PlaybackPitchCalculator`
- each new preview clears the previous preview voice before scheduling the replacement
- matching tracker note `keyUp` immediately cancels the active preview voice only
- keyUp does not write pattern `===`; backtick remains the explicit pattern key-off
- preview gain uses loaded-module adapter sample gain at neutral channel/global volume, default runtime output headroom, and a final preview-only safety cap
- no full gain/loudness parity with normal Play/song playback yet
- no envelope processing
- no XM effect processing
- no pattern timing
- no loop handling
- no full FT2/XM key-off envelope or fadeout release parity

Preview is not attempted outside Edit-mode note input, for blank documents without real sample payload, key-off requests, clear/delete input, navigation, unsupported keys, unavailable selected instrument/sample state, or loaded-module samples without previewable PCM payload. Loaded modules remain read-only for pattern mutation, even when their sample descriptors are potentially previewable. Blank documents remain silent and preview-unavailable until sample import/loading/editor support provides real payload. Play/Stop transport and normal song playback remain unrelated to editor preview and unchanged by this preview sink.

## Deferred Work

- Non-Edit-mode keyboard audition.
- Full preview gain/loudness parity with normal Play/song playback, including global volume, channel volume, volume-column state, envelopes, and effect-derived gain changes.
- Full FT2/XM release, fadeout, envelope, effect, and loop-aware preview parity.
- User-addressable loaded-module sample-slot selection beyond the current sample-map placeholder.
- XI import, sample loading, instrument editor, and sample editor.
- Pattern loop while editing.
- Instrument entry, sample entry, effect entry, volume-column entry, and save/export behavior.
- Transport-coupled preview controls.

The next implementation step should define the non-Edit-mode note audition policy while preserving the current rule that pattern key-off remains explicit `===` entry through the backtick binding.

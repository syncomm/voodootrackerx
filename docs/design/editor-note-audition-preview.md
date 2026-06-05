# Editor Note Audition Preview Plan

This note defines the editor-side request shape for note audition preview. The current spike proves an isolated loaded-module sample audition path for Edit-mode note input with real public fixture sample payload, while keeping runtime song playback, transport state, backend selection, parser architecture, tracker viewport behavior, and loaded-module pattern mutability unchanged.

## Request Meaning

When Edit mode receives a tracker note key, the editor may create an `EditorNoteAuditionRequest` alongside the existing pattern note-entry action. The request is preview-only data: note value, selected octave, selected 1-based instrument/sample slots, source context, and optional row/channel context.

The current audible sink uses the resolved sample's base playback rate for a fixed/base-pitch one-shot preview. It carries the typed note value and selected octave through the routing event for later work, but it does not yet map the typed note/octave to playback pitch. The preview sink applies only sample volume plus a conservative local preview gain; it does not yet normalize against normal song playback loudness, module/runtime gain policy, global volume, channel volume, volume-column state, or envelope state. Maintainer headphone testing found the spike preview is still significantly louder than normal song playback, so full preview gain normalization remains deferred to a follow-up PR. Non-Edit-mode keyboard audition is deferred. Repeated AppKit keyDown events for tracker note keys do not retrigger preview, so a held key produces only the initial one-shot audition.

Key release should eventually send a preview-only key-off request for sustained or enveloped sounds. That release request must not write pattern data. Pattern key-off remains the explicit `===` note entry through the backtick/grave-accent key binding.

## Source Rules

Blank documents currently contain selected instrument/sample slots such as `I01`/`S01`, but no real instrument or sample payload. They are therefore preview-unavailable until a later milestone adds a real playable payload through import, sample loading, or editors.

Loaded modules may become auditionable before they become editable. Future loaded-module audition may resolve selected instrument/sample data from the loaded playback model, but it must not mutate loaded pattern data.

## Loaded-Module Sample Availability

Loaded-module preview availability resolves the editor note-audition request against the app-level `PlaybackSong` instrument/sample model. A selected instrument/sample is unavailable when the loaded playback song is missing, the selected instrument or sample slot cannot resolve, or the resolved sample has no playable PCM payload. A resolved sample with payload reports a descriptor containing the instrument index, sample index, frame count, loop metadata presence, source context, and a copied preview PCM payload.

Loaded XM preview now uses the editor's loaded-module selection state instead of hard-coding `I01`/`S01`. The existing instrument popup can update the selected instrument for preview. The sample popup is still a sample-map placeholder, so sample-slot switching remains tied to the current selected sample state, which defaults to `S01`, until a later sample/instrument selection milestone makes sample slots user-addressable.

This resolver does not play audio, schedule voices, call CoreAudio, or change playback transport behavior. Loaded modules may be previewable before they become editable. Blank documents remain preview-unavailable until they have real instrument/sample payload through later import or editor support.

Positive loaded-module preview availability is covered by the generated public
XM fixture `tests/reference-xm/generated/basic-instrument-sample.xm`, loaded
through the normal public fixture path and `PlaybackSongBuilder`. The test
proves selected `I01` / `S01` resolves to a real one-sample PCM payload and a
preview descriptor with copied PCM, volume, and parsed base sample rate. Loaded
modules remain read-only.

## First Preview Spike

The first routing spike added `EditorNoteAuditionPreviewer`, which consumes an `EditorNoteAuditionRequest` plus an `EditorNoteAuditionAvailability` result. It attempts preview only for note-on requests whose descriptor comes from a loaded module and reports real sample payload with a positive frame count and copied PCM payload. The previewer uses an injected sink so tests can verify request routing and metadata without CoreAudio or audio hardware.

The audible spike adds `EditorNoteAuditionAudioSink` behind the existing `EditorNoteAuditionPreviewSink` boundary. The sink owns a separate preview-only CoreAudio DefaultOutput unit and a separate `CSoftwareMixer` instance. It does not call `PlaybackEngine`, does not call runtime `PlaybackAudioOutput.trigger(_:)`, does not start or stop song transport, does not publish playback-follow positions, does not alter Play/Stop button state, and does not participate in offline render/export behavior.

The current audible preview is intentionally simple:

- loaded-module note-on requests only
- Edit-mode note input only
- selected instrument/sample must resolve to `.potentiallyAvailable(...)`
- repeated note-key `keyDown` events do not retrigger preview
- copied Float32 mono PCM payload must be non-empty
- one-shot C mixer voice
- fixed/base playback step from sample base rate to preview output sample rate
- typed note/octave is not yet mapped to playback pitch
- conservative fixed local preview gain
- maintainer testing found preview remains significantly louder than normal Play/song playback in headphones
- no full gain/loudness parity with normal Play/song playback yet
- no envelope processing
- no XM effect processing
- no pattern timing
- no loop handling
- no key-release/key-off behavior

Preview is not attempted outside Edit-mode note input, for blank documents without real sample payload, key-off requests, clear/delete input, navigation, unsupported keys, unavailable selected instrument/sample state, or loaded-module samples without previewable PCM payload. Loaded modules remain read-only for pattern mutation, even when their sample descriptors are potentially previewable. Blank documents remain silent and preview-unavailable until sample import/loading/editor support provides real payload. Play/Stop transport remains unrelated to editor preview.

## Deferred Work

- Preview key-release/key-off behavior.
- Non-Edit-mode keyboard audition.
- Typed note/octave to playback-pitch mapping.
- Preview gain normalization against normal Play/song playback.
- User-addressable loaded-module sample-slot selection beyond the current sample-map placeholder.
- XI import, sample loading, instrument editor, and sample editor.
- Pattern loop while editing.
- Instrument entry, sample entry, effect entry, volume-column entry, and save/export behavior.
- Envelope/effect/loop-aware preview.
- Transport-coupled preview controls.

The next implementation step should focus only on preview key-release/key-off behavior and must preserve the current rule that pattern key-off remains explicit `===` entry through the backtick binding.

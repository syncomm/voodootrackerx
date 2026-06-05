# Editor Note Audition Preview Plan

This note defines the editor-side request shape for future note audition preview. The current spike adds a preview coordinator and test sink seam, but it does not add audible playback, mixer calls, runtime transport changes, pattern playback, or instrument preview.

## Request Meaning

When Edit mode receives a tracker note key, the editor may eventually create an `EditorNoteAuditionRequest` alongside the existing pattern note-entry action. The request is preview-only data: note value, selected octave, selected 1-based instrument/sample slots, source context, and optional row/channel context.

Key release should eventually send a preview-only key-off request for sustained or enveloped sounds. That release request must not write pattern data. Pattern key-off remains the explicit `===` note entry through the backtick/grave-accent key binding.

## Source Rules

Blank documents currently contain selected instrument/sample slots such as `I01`/`S01`, but no real instrument or sample payload. They are therefore preview-unavailable until a later milestone adds a real playable payload through import, sample loading, or editors.

Loaded modules may become auditionable before they become editable. Future loaded-module audition may resolve selected instrument/sample data from the loaded playback model, but it must not mutate loaded pattern data.

## Loaded-Module Sample Availability

Loaded-module preview availability resolves the editor note-audition request against the app-level `PlaybackSong` instrument/sample model. A selected instrument/sample is unavailable when the loaded playback song is missing, the selected instrument or sample slot cannot resolve, or the resolved sample has no playable PCM payload. A resolved sample with payload reports an inert descriptor containing the instrument index, sample index, frame count, loop metadata presence, and source context.

This resolver does not play audio, schedule voices, call CoreAudio, call the C mixer, or change playback transport behavior. Loaded modules may become previewable before they become editable. Blank documents remain preview-unavailable until they have real instrument/sample payload through later import or editor support.

Positive loaded-module preview availability is covered by the generated public
XM fixture `tests/reference-xm/generated/basic-instrument-sample.xm`, loaded
through the normal public fixture path and `PlaybackSongBuilder`. The test
proves selected `I01` / `S01` resolves to a real one-sample PCM payload and an
inert `EditorNoteAuditionSampleDescriptor`; audible preview remains deferred,
and loaded modules remain read-only.

## First Preview Spike

The first spike adds `EditorNoteAuditionPreviewer`, which consumes an `EditorNoteAuditionRequest` plus an `EditorNoteAuditionAvailability` result. It attempts preview only for note-on requests whose descriptor comes from a loaded module and reports real sample payload with a positive frame count. The previewer uses an injected sink so tests can verify request routing and metadata without CoreAudio or audio hardware.

Actual audible preview is deferred. The existing runtime `PlaybackAudioOutput.trigger(_:)` path is coupled to song playback voices, runtime diagnostics, and transport stop/reset behavior, so this PR does not use it for editor audition. The default app sink is intentionally no-op until a dedicated preview backend can play short one-shot samples without changing runtime song playback behavior.

Preview is not attempted for blank documents without real sample payload, key-off requests, clear/delete input, unavailable selected instrument/sample state, or loaded-module samples without previewable PCM payload. Loaded modules remain read-only for pattern mutation, even when their sample descriptors are potentially previewable. Blank documents remain preview-unavailable until sample import/loading/editor support provides real payload.

## Deferred Work

- Actual note audition audio playback.
- CoreAudio, C mixer, runtime transport, or offline-render integration for editor preview.
- XI import, sample loading, instrument editor, and sample editor.
- Pattern loop while editing.
- Instrument entry, sample entry, effect entry, volume-column entry, and save/export behavior.

The first implementation step after this planning seam should focus only on loaded-module preview availability from safely resolved sample data.

# Editor Note Audition Preview Plan

This note defines the editor-side request shape for future note audition preview. It does not add audio playback, mixer calls, runtime transport changes, pattern playback, or instrument preview.

## Request Meaning

When Edit mode receives a tracker note key, the editor may eventually create an `EditorNoteAuditionRequest` alongside the existing pattern note-entry action. The request is preview-only data: note value, selected octave, selected 1-based instrument/sample slots, source context, and optional row/channel context.

Key release should eventually send a preview-only key-off request for sustained or enveloped sounds. That release request must not write pattern data. Pattern key-off remains the explicit `===` note entry through the backtick/grave-accent key binding.

## Source Rules

Blank documents currently contain selected instrument/sample slots such as `I01`/`S01`, but no real instrument or sample payload. They are therefore preview-unavailable until a later milestone adds a real playable payload through import, sample loading, or editors.

Loaded modules may become auditionable before they become editable. Future loaded-module audition may resolve selected instrument/sample data from the loaded playback model, but it must not mutate loaded pattern data.

## Deferred Work

- Actual note audition audio playback.
- CoreAudio, C mixer, runtime transport, or offline-render integration for editor preview.
- XI import, sample loading, instrument editor, and sample editor.
- Pattern loop while editing.
- Instrument entry, sample entry, effect entry, volume-column entry, and save/export behavior.

The first implementation step after this planning seam should focus only on loaded-module preview availability from safely resolved sample data.

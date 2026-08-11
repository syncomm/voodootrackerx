# ADR 013: Visible-Range Keymap Ownership Projection

## Status

Accepted. This decision supersedes only ADR 012's transient full-map graphical-selection and
ownership-display direction. ADR 012's canonical 96-note document map and mutation contract remain
in force.

## Problem

The Instrument Editor placed a full C-0...B-7 ownership summary above a movable three-octave piano.
They shared a width but used different note scales, so committed ownership appeared above the wrong
visible keys even though document mapping and audition resolution were correct.

## Decision

- The canonical 96-entry keymap remains authoritative in the document.
- The ownership strip and piano consume the same `InstrumentKeyboardVisibleRange`; the strip projects
  exactly its 36 notes and never derives a second range.
- `InstrumentEditorKeyboardLayout` supplies both surfaces' horizontal geometry. Each interior ownership
  boundary is the midpoint between neighboring note-key frame centers; the visible range edges use the
  keyboard content edges. Contiguous cells with the same owner may render as one segment.
- The strip is committed-state display only. It has no hit target, selection, drag, mutation, or sheet
  prefill behavior. `MAP RANGE…` remains the sole current assignment UI over C-0...B-7.
- Range navigation refreshes both surfaces without document revision, undo history, or selection changes.
  Loaded read-only modules use the same projection while assignment remains disabled.

## Rationale

One range and one note-to-x geometry remove the incompatible-scale failure by construction. Key-frame
midpoints preserve alignment across nonuniform white/black key shapes, layout widths, and backing scales
without hard-coded screen coordinates or a full-96 proportional formula.

## Impact And Tradeoffs

The strip no longer summarizes hidden notes; range navigation reveals other portions of the authoritative
map. Tests must pin 36 visible cells, C-5...B-5 as exactly 12 semitones, the C-5 and C-6 piano/ownership
boundaries, navigation non-mutation, selected-sample independence, undo/redo refresh, and read-only parity.
This decision changes no file format, parser/writer, resolver, audition/playback, mixer, or tracker viewport.

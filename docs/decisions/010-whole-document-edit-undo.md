# ADR 010: Whole-Document Edit And Undo Funnel

Status: Accepted for editable app documents.

## Context

`BlankTrackerDocument` is a value-like, Equatable model already replaced
wholesale by editor operations. Future destructive edits need one mutation and
refresh boundary; loaded modules and opened source paths must remain outside it.

## Decision

Use `EditableDocumentEditCoordinator.applyEdit` for new instrument/sample
mutations. Each label captures the prior document, applies a new value through
existing refresh paths, and registers reciprocal snapshots with a 20-level
`UndoManager`.

The context carries no source URL. Loaded read-only and playback-active states
cannot apply, undo, or redo. Clear Current Pattern is the first routed mutation;
unmigrated data mutations clear history until migrated deliberately.

## Consequences

- undo/redo restores exact editable-document values and refreshes the tracker,
  control panel, Song / Order editor, and read-only Instrument Editor
- File New, module load, and editable-copy boundaries discard prior history
- Save/Save As, export ownership, instrument/sample editing, playback,
  scheduling, mixer DSP, parser, XM writer, and tracker viewport are unchanged

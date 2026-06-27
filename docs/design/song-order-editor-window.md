# VoodooTracker X — Song / Order Editor Window

**Window:** Song / Order editor (independent floating utility window).
**Fixed size (first pass):** ~660 × 480.
**Mockup:** `assets/mockups/song-order-editor-v1.html`.
**Status:** Design-only. Does not change playback, the tracker viewport, the parser, or audio backend.

See `docs/design/editor-window-design-overview.md` for the shared direction and
`docs/design/editor-control-vocabulary.md` for the controls.

---

## 1. Purpose and mental model

The Song / Order editor is the **arrangement spine** of a module: *the order list is the song.* A
song is an ordered sequence of **order slots**, each pointing at a **pattern number**. The same
pattern can appear in many slots; reordering slots rearranges the song without touching pattern
content.

The window also owns **pattern-bank operations** (create / duplicate / clear a pattern) and
song/pattern transport for auditioning arrangement choices.

The clarity goal: **the user must never confuse an order position with a pattern number.** Order
position = *where in the song* (slot index). Pattern number = *which pattern plays there.* The layout
makes this distinction structural — a dim order-index column versus a bright pattern-number segment.

This is a **compact spine**, not a large arrangement timeline (out of scope).

### Deliberately omitted: transport + song meta

Transport (play/stop/loop) and song meta (title, length, current position, restart) are **not
repeated here** — they live in the main control panel, which stays open alongside this window.
Duplicating them would add clutter with no benefit.

---

## 2. Primary user workflows

1. **Build an arrangement:** select an order slot → set its pattern number → insert the next slot →
   repeat. Move slots up/down to reorder sections.
2. **Reuse a pattern:** insert a slot pointing at an existing pattern (e.g. a recurring chorus);
   duplicate a slot to copy its pattern reference.
3. **Author a new section:** "New pattern" allocates an unused pattern and points the current slot at
   it; jump to the tracker to fill it in.
4. **Reset safely:** "Clear Song" wipes order/arrangement data while **preserving instruments and
   samples**, so the user can start a new arrangement with the same instrument set.

---

## 3. Visual layout

Two main columns (order list spine on the left, pattern bank on the right), with full-width op rows
below.

```
┌─ Song / Order ───────────────────────────────────────────────┐
│ ┌─ ORDER LIST ─────────────┐  ┌─ PATTERN BANK  000–063 ◀▶ 1/4 ┐│
│ │ ORD │ PTN │ ROWS          │  │ [00][01]…[12●]…[15]            ││
│ │ 010 │ 012 │ 064  ◀ sel    │  │ [16]……………………[63]            ││
│ │ …scrolls…                 │  │  ▓=used  ●=current  □=empty    ││
│ │ ORD=position PTN=pattern  │  └───────────────────────────────┘│
│ └───────────────────────────┘  ┌─ PATTERN OPS ─────────────────┐│
│                                 │ [NEW][DUP][CLEAR]             ││
│                                 └───────────────────────────────┘│
│ ┌─ ORDER OPS ─────────────────────────────────────────────────┐ │
│ │ [INSERT][DELETE][DUP] | [MOVE UP][MOVE DOWN] | PTN [−][+]    │ │
│ └─────────────────────────────────────────────────────────────┘ │
│ ┌─ DANGER ────────────────────────────────────────────────────┐ │
│ │ [CLEAR SONG]  (keeps instruments + samples)                 │ │
│ └─────────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
```

The selected order row uses the indigo selection highlight (the tracker's highlight hue). The current
pattern in the bank is marked with a small red indicator LED.

---

## 4. Control groups

- **ORDER LIST:** scrollable order slots (index · pattern segment · row count). Primary interaction
  surface; selection drives every op and the pattern stepper.
- **PATTERN BANK:** a paginated grid of pattern slots (e.g. 64 per bank with prev/next + a bank
  readout, since a song can reference many patterns). Marks current and used patterns; click to jump
  / point the selected slot.
- **PATTERN OPS:** New (blank) pattern, Duplicate current pattern, Clear current pattern.
- **ORDER OPS:** Insert / Delete / Duplicate slot, Move up / down, and Pattern −/+ for the selected
  slot.
- **DANGER:** Clear Song (arrangement only; preserves instruments + samples), set apart with a muted
  red border and a deliberate confirm.

---

## 5. Required controls for v1.0

Order list with selected position; pattern number per slot (clearly distinct from order index);
insert/delete/duplicate slot; move up/down; pattern −/+; new/duplicate/clear pattern; clear song data
preserving instruments+samples; play song / play pattern / loop pattern (via the existing transport);
paginated pattern bank overview; unmistakable order-vs-pattern distinction.

---

## 6. Nice-to-have controls for later

Drag-to-reorder slots; per-slot section names / color tags; orphan-pattern detection and "find unused
patterns" cleanup; multi-select for block move/delete; pattern usage counts.

---

## 7. What not to include yet

No DAW-style arrangement timeline; no per-slot tempo/speed automation; no pattern-content thumbnails
inside the bank grid (keep it a label/state grid); no cross-module pattern import in this window.

---

## 8. Interaction notes

- Selecting a slot binds all Order Ops and Pattern −/+ to that slot; Insert places a new slot after
  the selection and selects it; Delete selects the previous slot.
- Pattern −/+ and the bank grid edit the **selected slot's** pattern reference; they never create a
  pattern (use New Pattern for that).
- Transport actions here drive the same engine as the main window — no second playback path.
- Clear Song is a deliberate danger action; it must provably preserve the instrument and sample
  tables.

---

## 9. Keyboard / navigation notes

Up/Down move order selection; `+`/`-` (or `]`/`[`) change the selected slot's pattern number; `I`
insert, `Delete`/`Backspace` delete, `D` duplicate; `Cmd+↑`/`Cmd+↓` move the slot; Space follows the
main window's transport semantics; Tab cycles order list → pattern bank.

---

## 10. AppKit implementation notes (for a future PR)

- Fixed-size window (non-resizable mask, first pass); single shared instance toggled from a menu item.
- **Order list:** a view-based table (or collection view) with index / pattern / rows columns; custom
  cell drawing applies the segment styling to the pattern value and the dim style to the index; indigo
  selection.
- **Pattern bank:** a collection/grid view of fixed cells with current/used state styling and
  pagination.
- Reuse the shared stepper, segment readout, button, and indicator-LED components.
- Route pattern/order mutations through the existing document command layer so undo/redo and
  dirty-tracking stay consistent; Clear Song must preserve instruments/samples.
- Bind transport to the existing transport surface; do not create a new playback path or alter mixer
  timing.

### Suggested PR sequence

1. Window shell + menu toggle.
2. Order list table (read-only) bound to document order data.
3. Order ops wired to document commands.
4. Pattern ops wired to document commands.
5. Pattern-bank grid (overview + jump + pagination).
6. Transport bindings (play song/pattern, loop).
7. Clear-song danger action (preserves instruments/samples).

---

## 11. Testing / manual verification

Screenshot before/after each PR. Verify the order-vs-pattern distinction reads without explanation.
Functional: insert/delete/dup keep selection sane; move preserves pattern refs; pattern −/+
wraps/clamps; New Pattern allocates an unused pattern; Clear Song leaves instruments and samples
intact (assert those tables are unchanged). Transport behaves identically to the control panel with no
second path. Closing returns focus to the tracker; reopening focuses the same instance.

---

## 12. Risks and open questions

- Keep the pattern-bank grid a label/state grid to avoid implying content preview. If risky, ship
  order-list-only first and add the grid later.
- Verify order-vs-pattern is unmistakable with a fresh user.
- Open: pattern numbering format in the editor (decimal vs hex) — default decimal, matching the
  control-panel decision; tracker viewport row numbers stay hex per the behavior spec.
- Open: drag-to-reorder vs. move buttons for v1.0 (buttons assumed).

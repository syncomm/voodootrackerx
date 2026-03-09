# VoodooTracker X — Tracker Behavior Specification

This document defines the canonical behavior of the VoodooTracker X Track Editor.

All UI and navigation logic must follow this specification.  
If behavior is ambiguous, implementations should match the legacy VoodooTracker behavior where possible.

Reference image:

assets/screencapture/voodootracker-classic.jpg

---

# Core Principle

The **track editor is the central component of the application**.

Composition speed, visual rhythm clarity, and keyboard workflow take priority over UI novelty.

---

# Static Cursor Row

The track editor uses a **static highlight row**.

The highlight row does **not move vertically** during navigation or playback.

Instead, pattern content scrolls behind it.

Purpose:

- allow the composer to see upcoming notes
- provide rhythmic focus while editing
- match classic tracker workflow

---

# Anchor Position

The static highlight row should appear approximately **midway down the visible tracker viewport**.

Example layout:

(blank rows)  
(blank rows)  
Row 00 ← static highlight row  
Row 01  
Row 02  
Row 03  

Blank rows above Row 00 are normal when a pattern first loads.

---

# Initial Pattern Load

When a pattern loads:

- Row 00 is positioned at the static highlight row.
- Empty background appears above it.
- No fake rows should be generated.

---

# Navigation

## Down Arrow

Down arrow increments the active row.

Behavior:

- Highlight row remains fixed.
- Pattern content scrolls upward behind the highlight row.

Example:

Before:

Row 00 ← highlight  
Row 01  
Row 02  

After pressing Down:

Row 01 ← highlight  
Row 02  
Row 03  

---

## Up Arrow

Up arrow decrements the active row.

Behavior:

- Highlight row remains fixed.
- Pattern content scrolls downward behind the highlight row.

---

# Pattern Wraparound

Navigation wraps at pattern boundaries.

Last Row + Down → Row 00  
Row 00 + Up → Last Row

The highlight row remains fixed during wraparound.

---

# Pattern Length

Only real rows from the pattern should be rendered.

Extra viewport space should appear as **empty background**, not numbered rows.

Incorrect behavior:
62
63
64
65 <-- fake rows
66

Correct behavior:
62
63
(blank)
(blank)


---

# Row Number Gutter

Row numbers appear in a **fixed left gutter**.

Rules:

- gutter must not scroll horizontally
- gutter must remain vertically aligned with pattern rows
- gutter uses hexadecimal row numbering (00–FF)

Example:
00 | C-4 01 .. ...
01 | --- .. .. ...
02 | D#4 02 .. ...


---

# Channel Columns

Each channel contains:

NOTE | INSTR | VOL | EFFECT

Example:
C-4 01 .. A01


Column widths must be constant.

---

# Beat Highlighting

Every **4 rows** should be visually emphasized to help track rhythm.

Example:

Row 00 ← strong highlight  
Row 01  
Row 02  
Row 03  
Row 04 ← strong highlight  

---

# Cursor Behavior

The cursor highlights the active field within the row.

Fields:

NOTE  
INSTRUMENT  
VOLUME  
EFFECT TYPE  
EFFECT PARAMETER

The active field is displayed with a **red rectangle**.

Cursor must never be clipped at viewport edges.

---

# Horizontal Scrolling

Horizontal scrolling moves channel columns only.

Row numbers and pattern row alignment must remain stable.

Channel headers must stay aligned with channel columns.

---

# Mouse Scrolling

Mouse wheel scrolling should behave the same as keyboard navigation.

The highlight row must remain static.

Incorrect behavior:

- highlight row moving vertically

Correct behavior:

- pattern rows scrolling behind highlight row

---

# Editing Modes

Track editor supports multiple interaction modes.

Navigation Mode
- movement only
- no data mutation

Edit Mode
- hex entry allowed
- delete clears field

Play Mode
- future playback state

Record Mode
- future live note entry

---

# Rendering Performance

The pattern editor must remain smooth even with:

- 64+ channels
- long patterns
- large modules

Rendering should avoid excessive per-cell UI elements.

Preferred approach:

- custom view drawing
- minimal layout recalculation


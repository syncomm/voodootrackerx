# VoodooTracker X — Control Panel UI Design Spec

**Branch:** `design/control-panel-redesign`  
**Scope:** Main window control panel only (two-row strip below the logo panel).  
**Status:** Design specification and mockups. No code changes in this PR.

---

## 1. Context

The control panel sits between the VoodooTracker X logo and the pattern grid. It is the primary
interface for pattern editing: transport control, song navigation, pattern/instrument selection,
and playback parameter adjustment. Separate windows will eventually house the Song Editor,
Instrument Editor, and Sample Editor — this panel stays lean and focused on the live editing
workflow.

### What the panel needs to do

1. Start / stop / loop / toggle edit mode (transport)
2. Show and navigate song position (title, length, order position, restart)
3. Select the active pattern and set its row count
4. Select the active instrument and sample slot
5. Set tempo (BPM) and speed (ticks per row) — **must be directly editable, not just readouts**
6. Select the editor octave
7. Show channel count (readout only)

---

## 2. Current State Critique

### Widget correctness

| Control | Current widget | Recommendation |
|---|---|---|
| PLAY / STOP | Momentary NSButton | Keep. Differentiate active state with color. |
| LOOP / EDIT | Toggle NSButton | Keep. Gold tint when active is good. |
| TITLE | Readout NSTextField | Keep. Editable title is a future milestone. |
| Song time (03:25) | Appended to TITLE string | **Split out** as its own labeled TIME readout. |
| LEN | Readout NSTextField | Keep (song length in orders is a readout). |
| POS | Readout + NSStepper | Keep. Stepper is correct here. |
| RST | Readout NSTextField | Keep (restart order is a readout). |
| PTN (was PATTERN) | NSPopUpButton | Label shortened to PTN — saves ~25px, giving INST/SMP more room for names. **Display as zero-padded decimal (001, 012, 111)** — not hex (0C) or prefixed (P0C). The label already says PATTERN so the prefix is redundant; decimal is readable by everyone without tracker background. |
| ROWS | Readout NSTextField | **Add stepper arrows.** Range 16–256 (powers of 2 plus 192). |
| INST | NSPopUpButton | Keep. **Display format: dim gold code prefix (I01) + warm white name (Drums)**. Truncate name at ~12 chars with ellipsis; full name in tooltip. Opened dropdown items: "I01 — Drums", "I02 — 808 Snare". When no name is set, code fills the full field width (fallback to current behavior). |
| SMP | NSPopUpButton | Keep. Same name-display treatment as INST: "S01 · 808 Kick". |
| TEMPO | **Readout NSTextField** | **Make editable with stepper arrows.** Range 32–255. |
| SPEED | **Readout NSTextField** | **Make editable with stepper arrows.** Range 1–31. |
| OCT | NSPopUpButton | Keep (0–8 range). |
| CHN | Readout NSTextField | Keep (readout only; set at document creation). |

### Visual issues

- All readout fields share identical visual style with interactive controls — no hierarchy.
- No visual grouping between logical sections (transport / song / pattern / instrument / timing).
- Standard macOS stepper and popup chrome reads as generic macOS app, not tracker hardware.
- Right side of both rows trails off into dead whitespace.
- The gold accent color (#C9A74A) on labels is correct and must be preserved.
- Zero corner radius combined with no surface differentiation makes the panel feel flat and
  characterless.

---

## 3. Design Principles

### Aesthetic: Dark Hardware Synth Panel

The VoodooTracker X logo stakes out graffiti/street art territory. The control panel should
feel like the hardware underneath that logo — a dark, precision instrument. Think Roland TR-808,
Yamaha DX7, Akai MPC: matte dark surfaces, labeled group sections, LED-style numeric readouts,
tactile-feeling buttons with clear active states.

This is **not** a CRT terminal look (too lo-fi, fights the logo) and **not** a modern minimal
flat app (too corporate). It is a dark hardware workstation panel, filtered through the tracker
tradition.

### Principles

1. **Group before you label.** Controls belong to logical sections. Each section gets a thin
   vertical separator and (optionally) a micro-label above it. Groups: TRANSPORT / SONG / POSITION /
   PATTERN / INSTRUMENT / TIMING / EDIT.

2. **Differentiate readouts from interactive controls.** Pure readouts (LEN, RST, CHN) should
   look slightly recessed/inert. Interactive controls (POS+stepper, TEMPO+stepper, SPEED+stepper,
   ROWS+stepper, popups) should feel like they can be touched.

3. **Active state must be visible.** PLAY should glow green when playback is running. LOOP and
   EDIT should glow gold (#C9A74A) when toggled on. STOP should appear dim/disabled when not
   playing.

4. **Fill the width.** The flexible spacer on the right currently wastes space. The SONG group
   (TITLE) should be the flexible element that expands to fill the row — it already does, but
   the bottom row should also fill its width gracefully.

5. **Keep the monospace.** The monospace font for all control labels and values is correct and
   must be preserved. It is core to the tracker identity.

---

## 4. Color Palette

Extends the existing `TrackerTheme.legacyDark` and `TrackerChromePalette`:

| Role | Hex | Usage |
|---|---|---|
| Window background | `#1E1E1E` | Window fill (unchanged) |
| Control panel surface | `#252526` | Panel background (unchanged) |
| Readout field background | `#1A1A1B` | Slightly darker than panel — recessed look |
| Interactive field background | `#1E1E1E` | Match window bg — feels inset/active |
| Group separator | `#C9A74A` at 38% opacity | Vertical divider lines between groups |
| Accent gold | `#C9A74A` | Labels, active toggle state, borders on interactive fields |
| Subtle border | `#C9A74A` at 22% opacity | Readout field border (existing, keep) |
| Interactive border | `#C9A74A` at 55% opacity | Slightly more visible on editable fields |
| Panel top edge | `#C9A74A` at 60% opacity | Thin 1px accent line at very top of panel |
| PLAY active glow | `#3A9C4F` | Green tint when playback is running |
| LOOP/EDIT active | `#C9A74A` | Gold tint when toggles are on (existing) |
| STOP active | `#CC3A2F` at 70% opacity | Subtle red tint when playback is running |
| Numeric readout text | `#E8D8A0` | Warm near-white for values (slightly warmer than labels) |
| Section micro-label | `#C9A74A` at 60% opacity | Small ALL-CAPS label above each group (optional) |

---

## 5. Layout Specification

### Panel height

Current: 112px. **Increase to 120px** to give breathing room for optional group micro-labels
and the top accent line. If group micro-labels are omitted in the first pass, 112px is
acceptable.

### Top accent line

A 1px horizontal line at the very top edge of the panel, color: `#C9A74A` at 60% opacity.
This visually "caps" the panel and separates it from the logo area with hardware-panel authority.

### Row 1 — Transport and Song

```
[TRANSPORT GROUP]  |  [SONG GROUP ─ flexible]  |  [POSITION GROUP]
  ▶PLAY ■STOP       TITLE  black light  03:25    LEN 111  POS 00⬆  RST 00
  ↺LOOP ⊙EDIT
```

Groups separated by vertical separator lines (1px, gold at 38% opacity), padded 8px on each side.

The TITLE field and the TIME display (currently concatenated) should be **two separate fields**:
- `TITLE` — flexible NSTextField readout, left-aligned, fills available width
- `TIME` — fixed-width readout showing playback time (e.g. `03:25`), right-aligned

### Row 2 — Pattern and Editor Controls

```
[PATTERN]  |  [INSTRUMENT]  |  [TIMING]  |  [EDIT]
 PAT  ROWS    INST   SMP      TEMPO SPEED   OCT CHN
[P0C⬍][128⬆⬇]  [I01    ⬍][S01     ⬍]  [183⬆⬇][02⬆⬇]  [4⬍][32]
```

Groups separated by the same vertical separator treatment.

The TIMING group (TEMPO + SPEED) should be the **standout visual group** on row 2 — these are the
controls users reach for most during live beat-laying. Consider slightly more separation padding
here.

---

## 6. Widget Visual Treatments

### Transport buttons (PLAY, STOP, LOOP, EDIT)

- Style: `.shadowlessSquare` bezel (existing), dark fill
- Border: 1px `#C9A74A` at 30% opacity (subtle but present)
- PLAY active state: background tint shifts to `#1A3A22` with green text `#3A9C4F`
- STOP: shows active (red tint bg `#3A1A1A`) only when playback is running; dim otherwise
- LOOP on: gold text `#C9A74A`, border at 60%
- EDIT on: gold text `#C9A74A`, border at 60%
- Height: 28px (unchanged)

### Popup buttons (PATTERN, INST, SMP, OCT)

- Background: `#1E1E1E` (interactive field bg)
- Border: 1px `#C9A74A` at 55% opacity
- Text: `#E8D8A0` (warm near-white)
- Arrow indicator: use custom gold chevron drawn in accent color rather than macOS native arrow
- Height: 28px (unchanged)

### Editable stepper fields (TEMPO, SPEED, ROWS, POS)

The core pattern: a text field + stepper pair, where:
- The text field has border color `#C9A74A` at 55% (more visible than readouts)
- Background: `#1E1E1E`
- Stepper: styled with accent color; NSStepper control, small size
- Text: `#E8D8A0`

TEMPO and SPEED fields should be directly editable (set `isEditable = true`, validate on commit).

### Pure readout fields (LEN, RST, CHN, TITLE, TIME)

- Background: `#1A1A1B` (slightly darker than interactive — recessed)
- Border: 1px `#C9A74A` at 22% opacity (subtle, existing)
- Text: `#E8D8A0` for values, `#C9A74A` for labels
- `isEditable = false` (existing)

The recessed background is the primary visual cue that these are readouts, not inputs.

### Control labels

- Font: monospaced semibold 12pt (existing `TrackerThemeFonts.controlLabel`)
- Color: `#C9A74A` (existing accent — keep)
- All caps (existing — keep)

### Group separators

A thin NSView with fixed width 1px, background color `#C9A74A` at 38% opacity, full height of
the row stack, with 8px horizontal margin on each side (16px total horizontal footprint per
separator).

### Optional group micro-labels (v2 consideration)

Small 9pt monospace text above each group, e.g. "TRANSPORT", "SONG", "PATTERN", etc., at
`#C9A74A` 55% opacity. Makes the panel read like a hardware mixer strip. Can be omitted in a
first coding pass if layout complexity is an issue — the separators alone carry the grouping.

---

## 7. Bottom Row Fill Strategy

The bottom row ends with a plain `makeFlexibleSpacer()` (invisible, just eats remaining width).
The INST and SMP popup fields are wide enough to show names (min ~130px each), which naturally
fills the row better than before.

**No activity meters in the control panel.** Visualization (waveform scopes, per-channel
activity) belongs behind the logo panel as part of the planned fade+visualization feature.
The control panel stays focused on controls only.

---

## 8. Logo Panel Future Note

The logo panel is currently 260px tall with a static image on a white background. The planned
future state:
- Logo image fades to ~85% transparency
- Behind/under the logo: a waveform/spectrum visualization or channel bar visualization
- Background: dark (#1E1E1E) rather than white, so the logo blends into the app surface

The control panel design should not depend on the logo panel height. When the logo panel
changes (shorter, with visualizer), the control panel stands independently.

---

## 9. Implementation Notes for Coding Agents

When implementing this design:

1. Read `docs/design/UI-DESIGN-control-panel.md` (this file) and `TrackerTheme.swift` first.
2. All color changes go in `TrackerChromePalette` and a new `TrackerControlPalette` enum in
   `TrackerTheme.swift`.
3. All layout changes go in `TrackerThemeMetrics.ControlPanelLayout` and `ControlPanelSizing`.
4. Widget changes (making TEMPO/SPEED editable, adding steppers to ROWS) go in
   `ControlPanelView.swift` and `ControlPanelDisplayState.swift`.
5. The song time field (`TIME`) split from the TITLE string requires a new outlet and wiring
   in `TrackerWindowController.swift` and `ControlPanelDisplayState.swift`.
6. Make changes in small, verifiable PRs per `AGENTS.md`. Do not combine widget changes with
   palette changes in the same PR.
7. Manual visual verification required per `docs/visual-verification.md` — screenshot before
   and after each PR.
8. Do not change tracker viewport behavior, audio backend, or parser behavior in these PRs.

### Suggested PR sequence

1. `ui: split song time display from title field` — extract TIME as a separate readout
2. `ui: add group separator views to control panel` — vertical dividers between groups
3. `ui: apply recessed/interactive field differentiation` — two-tier background treatment
4. `ui: make TEMPO and SPEED editable with steppers` — functional change, requires wiring
5. `ui: add stepper to ROWS field` — functional change
6. `ui: refine transport button active states` — PLAY green, STOP red, LOOP/EDIT gold
7. `ui: widen INST and SMP popups to fill bottom row` — layout completion

---

## 10. Mockup Reference

See `assets/mockups/control-panel-v1.html` for an interactive HTML mockup of the redesigned
control panel showing the hardware synth panel aesthetic with sample data.

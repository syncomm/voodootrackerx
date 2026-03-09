# VoodooTracker X — Development Session Bootstrap

This document provides the **minimal context required** for starting a development session on VoodooTracker X.  
Agents and developers should read this first before performing any work.

The goal is to reduce context loading, prevent architectural regressions, and ensure changes follow the intended design.

---

# Project Overview

VoodooTracker X is a modern open-source tracker inspired by classic trackers such as:

- FastTracker II
- VoodooTracker (legacy)
- Renoise (modern influence)

The focus of the project is:

- a faithful tracker workflow
- modern architecture
- extensibility for future AI-assisted features
- clean and maintainable UI architecture

The **Track Editor** is the core component of the application.

---

# Core UI Principle

Tracker UI behavior must match traditional tracker workflow.

The most important invariant:

**The highlight row is static while pattern rows scroll behind it.**

This allows composers to focus on the beat while seeing upcoming notes.

---

# Tracker Editor Architecture

The Track Editor follows these rules:

### 1. Static Highlight Row

The highlight row stays fixed in the viewport.

Pattern rows scroll behind it during:

- playback
- navigation
- editing

---

### 2. Shared Slot Model

The viewport is rendered using a **slot list**.

Each visible slot represents:

slotIndex → patternRow (or nil)

Slots may contain:

- a real pattern row
- an empty row (for padding)

Both the **gutter** and **pattern body** must render from the same slot list.

---

### 3. Shared Geometry

The rendered Y position for a row must match across:

- gutter labels
- pattern body rows
- highlight row

If these differ, the UI will appear visually misaligned.

Model correctness does **not** guarantee visual correctness.

---

### 4. Initial Load Behavior

On initial load:

highlight row → pattern row 00

Rows above the highlight row may be blank.

Rows below the highlight row should display real rows until the pattern ends.

---

### 5. Wrap Behavior

Cursor navigation wraps:

last row → first row  
first row → last row

Scrolling and navigation must preserve static highlight behavior.

---

# Debugging UI Issues

When debugging tracker UI, use this document as the fast session bootstrap and then rely on:

- `docs/tracker-behavior-spec.md` for behavior rules
- `docs/ui-debugging.md` for debugging workflow
- `docs/visual-verification.md` for required visual checks

When debugging tracker UI:

### Step 1 — Reproduce the problem

Load a real module file if necessary.

### Step 2 — Capture a screenshot

Visual confirmation is often faster than code inspection.

### Step 3 — Confirm expected vs actual behavior

Example:

Expected:
row 00 appears on highlight row

Actual:
row 00 appears two rows below highlight row

### Step 4 — Verify model state

Check:

- slot mapping
- row indices
- viewport state

### Step 5 — Inspect rendered geometry

Log or inspect:

- gutter Y position
- pattern row Y position
- highlight row Y position

If these differ, the problem is **render geometry**, not model logic.

---

# UI Debugging Rules

When debugging visual alignment bugs:

Do:

- inspect rendered Y coordinates
- verify view/container geometry
- compare gutter/body layout origins
- use screenshots

Do not:

- repeatedly adjust offsets without identifying root cause
- assume model logic is the issue
- rely only on unit tests for visual bugs

---

# Acceptable Debugging Artifacts

Allowed during debugging:

- screenshots
- temporary logging
- local fixture module files

These **must not be committed to the repository.**

---

# Recommended Debugging Workflow

1. reproduce bug
2. capture screenshot
3. confirm expected vs actual behavior
4. inspect model state
5. inspect rendered geometry
6. simplify architecture if needed
7. verify visually

---

# Repository Structure (Simplified)

docs/
    architecture.md
    dev-roadmap.md
    tracker-behavior-spec.md
    ui-debugging.md
    dev-session-bootstrap.md

app/
    VoodooTrackerX/

legacy/
    voodootracker-classic/

---

# Development Roadmap

See:

docs/dev-roadmap.md

Major milestones include:

- tracker editor
- instrument editor
- sample editor
- module metadata
- audio engine
- scopes / visualizers
- plugin architecture
- future AI-assisted composition tools

---

# Context Loading Guidelines

Agents should load only the documentation required for the task.

For tracker UI work:

docs/dev-session-bootstrap.md  
docs/tracker-behavior-spec.md  
docs/ui-debugging.md  
docs/visual-verification.md  
docs/architecture.md  

For general project planning:

docs/dev-roadmap.md

Load `docs/task-templates.md` only when a task needs extra structure or a reusable execution pattern.

Avoid loading unnecessary documentation to reduce token usage.

---

# Development Philosophy

Priorities:

1. Correct tracker behavior
2. Clean architecture
3. Maintainable code
4. Iterative improvement

Architecture should favor **simplicity over cleverness**.

If multiple render paths produce the same UI result, prefer a **single shared pipeline**.

---

# Session Startup Checklist

Before beginning work:

1. Read this file.
2. Read the docs relevant to the task.
3. Confirm the current branch.
4. Understand the expected UI behavior.
5. Prefer visual verification for UI work.

---

End of bootstrap.

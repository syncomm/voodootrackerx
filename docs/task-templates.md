# Development Task Templates

This document provides common patterns for development tasks.

Agents may adapt these templates when performing work.

This file is optional context. Load it when a task needs extra structure or a reusable execution pattern, not as part of every session by default.

---

# UI Bug Fix Task

Goal: fix visual or layout issues.

Steps:

1. Reproduce bug.
2. Capture screenshot.
3. Describe expected vs actual behavior.
4. Inspect model state.
5. If model correct, inspect rendered geometry.
6. Simplify layout if needed.
7. Verify visually.

Commit only after visual verification.

---

# Viewport Logic Task

Goal: modify tracker viewport behavior.

Requirements:

- static highlight row
- shared slot mapping
- gutter/body alignment
- correct wrap behavior

Verification:

- initial load
- mid pattern
- bottom of pattern
- wrap navigation

---

# Parser or Data Model Task

Goal: modify module parsing or internal model.

Steps:

1. update parser
2. add or update unit tests
3. verify with real module files

Visual verification usually not required.

---

# Rendering Task

Goal: change how pattern grid is drawn.

Steps:

1. modify rendering code
2. verify geometry alignment
3. verify gutter/body mapping
4. perform visual verification

---

# Feature Development Task

Goal: implement new functionality.

Steps:

1. update architecture if needed
2. implement minimal working version
3. add tests where appropriate
4. perform manual verification

---

# Commit Guidelines

Commits should be:

- focused
- descriptive
- small when possible

Example commit message:

tracker: fix viewport gutter alignment

---

# Branch Guidelines

Feature branches should be used for non-trivial work.

Branch names should reflect the task.

Examples:

feature/track-editor-static-row  
feature/pattern-rendering  
feature/audio-engine

---

# Debugging Philosophy

Prefer **architectural fixes** over incremental patches.

If two components must stay visually aligned, prefer a **shared rendering pipeline**.

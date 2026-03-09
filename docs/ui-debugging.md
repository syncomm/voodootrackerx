# UI Debugging Guide

This document describes the recommended process for diagnosing and fixing UI issues in VoodooTracker X.

UI bugs frequently arise from differences between:

- the model/state logic
- the rendered geometry

Unit tests may pass while the visual output is still incorrect.

---

# General Debugging Workflow

1. Reproduce the issue consistently.
2. Capture a screenshot of the current UI state. When tooling permissions allow it, agents should capture their own screenshots instead of relying only on textual reports.
3. Describe the expected behavior.
4. Compare the expected result with the actual result.
5. Verify the underlying model and viewport state.
6. If the model is correct, inspect the rendered geometry.
7. If multiple render paths exist, simplify the layout and remove duplicated geometry logic where possible.

---

# Inspecting Model State

Confirm that the logical state is correct.

Examples:

- current pattern row
- viewport slot mapping
- visible row range
- cursor position

If the model is wrong, fix the model.

If the model is correct but the UI is wrong, the issue is likely rendered geometry.

---

# Inspecting Rendered Geometry

For visual alignment issues inspect:

- view frame origins
- clip view bounds
- content insets
- baseline offsets
- text layout origins
- scroll offsets

Log or print the coordinates used for:

- gutter row labels
- pattern body rows
- highlight row

These must match exactly for rows to align.

---

# Common Tracker UI Bugs

Typical causes include:

- separate layout pipelines for gutter and body
- mismatched viewport origins
- extra padding or insets
- baseline or font metric offsets
- separate row calculations

The preferred solution is usually simplifying the layout architecture.

---

# Debugging Rules

When debugging visual issues:

Do:

- capture screenshots early
- verify expected vs actual behavior
- inspect rendered geometry
- simplify layout if possible

Do not:

- repeatedly tweak offsets blindly
- assume passing tests guarantee correct rendering
- maintain parallel layout logic for the same rows

---

# Debug Artifacts

Temporary artifacts may include:

- screenshots
- logging
- local fixture modules

These must never be committed to the repository.

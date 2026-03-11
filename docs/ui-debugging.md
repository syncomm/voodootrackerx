# UI Debugging Guide

This document describes the recommended process for diagnosing and fixing UI issues in VoodooTracker X.

UI bugs frequently arise from differences between:

- the model/state logic
- the rendered geometry

Unit tests may pass while the visual output is still incorrect.

---

# General Debugging Workflow

1. Reproduce the issue consistently.
2. Use the project's canonical local build/run workflow before inventing alternate launch methods.
3. Capture a screenshot of the current UI state. When tooling permissions allow it, agents should capture their own screenshots instead of relying only on textual reports.
4. If reproduction can be automated, drive the UI with keyboard or mouse automation so the same scenario can be replayed repeatedly.
5. Describe the expected behavior.
6. Compare the expected result with the actual result.
7. Verify the underlying model and viewport state.
8. If the model is correct, inspect the rendered geometry.
9. Compare before/after screenshots for the same scenario after each meaningful change.
10. If multiple render paths exist, simplify the layout and remove duplicated geometry logic where possible.

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
- use the repo-standard build/run path
- verify expected vs actual behavior
- inspect rendered geometry
- automate reproduction when possible
- compare before/after screenshots
- simplify layout if possible

Do not:

- repeatedly tweak offsets blindly
- assume passing tests guarantee correct rendering
- maintain parallel layout logic for the same rows

Before risky UI iteration, create a checkpoint commit or tag so the last known-good state is easy to restore.

---

# Debug Artifacts

Temporary artifacts may include:

- screenshots
- logging
- local fixture modules

These must never be committed to the repository.

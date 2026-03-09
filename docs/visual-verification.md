# Visual Verification Guidelines

UI work must be visually verified before being considered complete.

Automated tests alone are insufficient for validating tracker UI behavior.

---

# When Visual Verification Is Required

Always verify visually when modifying:

- tracker viewport behavior
- gutter alignment
- scrolling logic
- cursor rendering
- channel layout
- pattern grid rendering

---

# Recommended Verification Procedure

1. Build and launch the application.
2. Load a real tracker module.
3. Capture screenshots of key states. When tooling permissions allow it, agents should capture their own screenshots instead of relying only on textual reports.

---

# Required Screenshot States

For tracker viewport changes verify at least:

1. **Initial Load**

Expected:
- row 00 on highlight row
- blank space above
- real rows below

---

2. **Mid Pattern**

Expected:
- highlight row remains static
- rows scroll behind it
- gutter and body aligned

---

3. **Bottom of Pattern**

Expected:
- real rows until the end
- blank rows only after pattern ends
- no phantom numbered rows

---

4. **Wraparound Navigation**

Expected:
- last row wraps to row 00
- row 00 wraps to last row
- highlight row remains fixed

---

# Screenshot Guidelines

Screenshots should be used for debugging but must not be committed.

If needed they may be temporarily saved locally during development.

---

# Local Test Modules

Real tracker modules may be loaded from a local directory.

These files must not be added to the repository due to potential copyright concerns.

---

# Expected Output Description

When reporting results include:

- screenshot
- expected behavior
- actual behavior

This document complements `docs/ui-debugging.md`. Use that guide for debugging workflow and this guide for deciding what visual states must be checked before calling UI work complete.

Example:

Expected:
row 00 aligned with highlight row

Actual:
row 00 appears two rows above highlight row


---

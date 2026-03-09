# UI Debugging Guide

Use this workflow for visual bugs, especially tracker viewport and alignment issues.

1. Reproduce the bug consistently.
2. Capture a screenshot. When tooling permissions allow it, agents should capture their own screenshots instead of relying only on textual reports.
3. Confirm the expected behavior versus the actual behavior.
4. Verify model and viewport state first.
5. If the model is correct, inspect rendered geometry next.
6. Log draw coordinates or final row positions that are actually rendered.
7. If multiple render paths exist, simplify the layout and remove duplicated geometry logic where possible.

Do not commit screenshots, local fixture files, or temporary logging.

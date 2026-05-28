# Post-Kxx Expanded Corpus Effect Refresh

Diagnostics-only local refresh after the minimal `Kxx` key-off PR. No playback
behavior, parser behavior, tracker UI behavior, runtime backend selection, C
mixer DSP behavior, or retired audio backends were changed for this report.

## Scope

- Corpus labels: `xm-corpus-001` through `xm-corpus-036`.
- Render path: bounded offline C mixer diagnostics through
  `vtx_render_bounded_xm --effect-coverage-json`.
- Render window: 60 seconds per input with row-windowed scheduling. A low
  sample-rate diagnostic carrier was used only to keep local WAV export time
  practical; command detection and row/tick status are the relevant evidence.
- Label source: reused the existing local-only private corpus label map.
- Generated artifacts: kept under `/tmp` and unstaged.
- Public safety: anonymized labels only; no private modules, paths, WAVs, JSON,
  logs, Markdown summaries, or label maps were committed.

## Aggregate Counts

| Metric | Count |
| --- | ---: |
| Inputs | 36 |
| Detected commands | 345,417 |
| Applied commands | 326,699 |
| Deferred commands | 2,242 |
| Unsupported commands | 2,227 |
| No-op / effect-memory-deferred commands | 16,487 |
| Effect-memory reuses | 8,921 |
| Effect-memory missing cases | 384 |
| Unknown commands | 23 |

The generic summary heuristic still surfaces `3xx tone portamento Follow-Up`
because it sees Amiga-table `3xx` rows as unsupported. This report separates
those rows into the Amiga frequency-table foundation bucket; linear-table `3xx`
has no unsupported/deferred implementation count in this refresh.

## Kxx Status

Before the Kxx PR, raw effect byte `0x14` was the targeted key-off gap. After
the PR, current bounded corpus diagnostics show `Kxx` is no longer an
unsupported/deferred bucket.

| Command | Detected | Applied | Deferred | Unsupported | No-active / no-op | First input | First coordinate |
| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `Kxx` key off | 3,029 | 3,002 | 0 | 0 | 27 | `xm-corpus-027` | order 1 pattern 33 row 62 ch 12 tick 0 |

All refreshed `Kxx` rows were in `xm-corpus-027`. The applied rows released an
active voice through the existing key-off/release path. The remaining 27 rows
were diagnosed as no-active-voice no-ops.

## Remaining Linear-XM Gaps

| Command | Count | Status | Best local target | Notes |
| --- | ---: | --- | --- | --- |
| `Rxy` multi retrigger | 414 | Deferred/unsupported | `xm-corpus-002` | Largest remaining linear-table deferred command, but retrigger volume-change behavior is broader than the smallest next PR. |
| `Xxy` extra fine portamento | 166 | Deferred/unsupported | `xm-corpus-031` | Compatibility-extension pitch work; keep separate from core linear-effect cleanup. |
| `5xy` tone portamento + volume slide | 56 | Deferred/unsupported | `xm-corpus-027` | Best narrow next effect PR: composes existing `3xx` tone-portamento state with the supported volume-slide gain path. |
| `Lxx` set envelope position | 25 | Deferred/unsupported | `xm-corpus-029` | Separate envelope-position foundation; defer behind narrower linear effects. |
| Volume-column tone portamento | 5 | Deferred/unsupported | `xm-corpus-034` | Small volume-column residual, not the next effect-column target. |

Linear-table `2xx` and `3xx` rows had no unsupported/deferred implementation
count in this refresh. Their remaining residuals were no-active, no-target,
no-speed, or ignored/no-op classifications.

## E0x Deferral

| Command | Total | Linear | Amiga-table | Status |
| --- | ---: | ---: | ---: | --- |
| `E0x` filter toggle | 401 | 82 | 319 | Deferred/limited usefulness |

`E0x` remains intentionally deferred. The refreshed count does not change its
limited-usefulness classification for v1 playback work.

## Amiga Frequency-Table Gaps

`xm-corpus-036` is the only Amiga-table input in this corpus pass.

| Command | Detected | Applied | Deferred | Unsupported | No-op | Notes |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `2xx` portamento down | 240 | 0 | 240 | 240 | 0 | Amiga-table pitch behavior remains a separate foundation target. |
| `3xx` tone portamento | 912 | 0 | 845 | 845 | 67 | Deferred rows are Amiga-table pitch behavior; no-target rows are safe no-ops. |

These are not linear-frequency regressions. They should stay grouped under a
future Amiga frequency-table foundation rather than a `3xx` linear-effect PR.

## Classification-Only Residuals

| Command | Count | Location | Status |
| --- | ---: | --- | --- |
| `Vxx` high-byte unknown | 4 | Linear-table inputs | Classification-only / unsupported |
| `Wxx` high-byte unknown | 19 | `xm-corpus-036` | Classification-only / unsupported |

No playback behavior should be inferred from these buckets. They remain visible
only so future compatibility decisions can classify them explicitly.

## Recommended Next PR

Recommended next narrow XM effect PR: **Minimal 5xy Tone Portamento + Volume
Slide**.

Rationale:

- It is a real linear-table effect-column gap in the refreshed corpus.
- The best local target is `xm-corpus-027`, which was already the top Kxx target.
- It should be narrower than `Rxy` multi retrigger because the current adapter
  already has first-pass `3xx` tone portamento and volume-slide foundations to
  compose.

Defer `Rxy`, `Xxy`, `Lxx`, `E0x`, Amiga frequency-table pitch behavior, and
`Vxx`/`Wxx` classification-only residuals to separate PRs.

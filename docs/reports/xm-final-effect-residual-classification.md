# XM Final Effect Residual Classification

Diagnostics-only local refresh after the focused `E4x` vibrato-control pass.
No XM effects, parser behavior, tracker UI behavior, runtime backend selection,
C mixer DSP behavior, or retired audio backends were changed.

## Scope

- Corpus labels: `xm-corpus-001` through `xm-corpus-026`.
- Label source: reused the existing local-only corpus label map.
- Generated artifacts: kept under `/tmp` and unstaged.
- Public safety: anonymized labels only; no private modules, paths, WAVs, JSON,
  logs, Markdown summaries, or label maps were committed.
- Tooling note: broad refreshes now use compact `--effect-coverage-json` output
  to avoid publishing or serializing full local diagnostics payloads.

## Findings

| Metric | Count |
| --- | ---: |
| Detected commands | 904,704 |
| Applied commands | 865,829 |
| Deferred commands | 87 |
| Unsupported commands | 72 |
| No-op / effect-memory-deferred commands | 38,802 |
| Effect-memory reuses | 4,174 |
| Effect-memory missing cases | 1 |
| Unknown commands | 0 |

`E0x` filter toggle is the only remaining unsupported/deferred concrete command
bucket. The prior `E4x` residual is covered: 9 detected `E4x` commands were
stored/applied, all observed as `E41`; no `E44...E4F` residuals were observed.

## Classification

| Bucket | Current result | Classification |
| --- | --- | --- |
| `E0x` filter toggle | 72 deferred/unsupported. | Limited-usefulness effect intentionally deferred. |
| `E4x` vibrato control | 9 stored/applied; only `E41` observed. | Diagnostic/classification cleanup only. |
| `EDx` note delay | 600 applied, 15 no-note deferred, 1 out-of-row no-op. | No-note and out-of-range safe residual. |
| `Dxx` / `Bxx` / `E6x` traversal | `Dxx` 29 applied + 1 out-of-range; `Bxx` 136 applied; `E6x` 28 applied. | Covered or out-of-range safe residual. |
| `900` memory | 2,685 memory reuses/applied, 1 missing-memory no-op. | Diagnostic/classification cleanup only. |
| `1xx` / `2xx` / `3xx` | Remaining 17 / 44 / 580 no-active, no-target, or ignored/no-op cases. | No-active safe residual. |
| `ECx` note cut | 13,998 applied, 473 no-active, 740 out-of-row no-ops. | No-active and out-of-range safe residual. |
| `E9x`, `Axy`, `Fxx`, key-off | Remaining cases are no-memory, ignored/no-op, or no-active classifications. | Diagnostic/classification cleanup only. |
| Volume-column vibrato / vibrato speed / tone portamento | Not observed in refreshed summary. | Unsupported but not observed in a meaningful playback path. |
| `xm-corpus-011` | Only 1 `EDx` no-note, 10 key-off no-active, and 1 ignored/no-op `Fxx`. | No concrete effect target. |
| `xm-corpus-025` | Only 1 `900` missing-memory no-op. | Classification cleanup only. |

## Recommendation

Recommended next PR: document `E0x` filter toggle as intentionally deferred,
then move to reference-render parity work. CoreAudio C mixer remains the
default runtime backend, and retired AVAudio backends were not reintroduced.

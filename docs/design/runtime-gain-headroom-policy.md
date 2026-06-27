# Runtime Gain And Headroom Policy

This note defines VoodooTracker X's current runtime gain/headroom policy and
the boundary between live playback diagnostics and offline export gain tools.
It is design documentation only and does not change playback behavior.

## Goals

- Keep live playback fast, predictable, and stable while modules load and play.
- Keep runtime output-level diagnostics visible without silently changing gain.
- Keep offline export/mastering policy separate from app/runtime playback.
- Give future pattern-loop, TIME, visualization, and export work a shared
  loudness, clipping, and diagnostic model.

## Current Runtime Policy

Runtime playback uses `RuntimeCMixerOutputPolicy` when the selected runtime
backend uses the C mixer. `PlaybackAudioOutputFactory` resolves the policy from
the process environment before the runtime C mixer output/backend is created.
The resolved policy is then carried by that runtime engine; it is not computed
per module and is not recomputed for every Play.

The default runtime policy is fixed headroom:

| Field | Current value |
| --- | --- |
| Default headroom | `-12 dB` |
| Default linear output gain | about `0.251189` |
| Headroom policy field | `runtime_headroom_policy=default_runtime_headroom_db` |
| Gain policy source | `runtime_gain_policy_source=default` |
| Runtime auto-headroom | `runtime_auto_headroom_enabled=false` |

Developer diagnostics may override the runtime output policy with environment
variables:

| Environment variable | Meaning |
| --- | --- |
| `VTX_C_MIXER_RUNTIME_GAIN` | Linear runtime output gain, greater than `0` and less than or equal to `1`. |
| `VTX_C_MIXER_RUNTIME_HEADROOM_DB` | Fixed runtime headroom in dB, less than or equal to `0`. |

Only one override may be used at a time. Invalid or conflicting values fall
back to the default policy and report a configuration warning in diagnostics.
These overrides are developer tools; they are not module-specific
auto-headroom.

`RuntimeCMixerRenderCore` applies the resolved output gain to the rendered
runtime output buffer, then records aggregate post-gain metrics such as
`output_peak`, `output_rms`, `overrange_sample_count`,
`clipping_sample_count`, and `clipping_detected`. Enabling
`VTX_RUNTIME_MIXER_METRICS_TRACE=1` records those values in sanitized stop
summaries. It does not run a module scan, change gain, change headroom, move
work from load to Play, or alter playback.

Runtime metrics report what happened under the active runtime policy. They do
not imply that the runtime policy was automatically adapted to the module.

## Current Offline And Export Policy

Offline render/export uses `MixerWAVExportPolicy`, which is intentionally an
export-boundary policy. The gain is applied after offline Float32 rendering and
before WAV encoding. It does not change mixer state, C mixer DSP, or runtime
playback.

Current export controls include:

| Export control | Meaning |
| --- | --- |
| `--gain N` | Apply explicit linear export gain before WAV encoding. |
| `--headroom-db N` | Apply explicit export headroom in dB before WAV encoding. |
| `--auto-headroom` | Compute export gain from the rendered Float32 block peak with the current `-1 dB` safety margin. |

`--gain`, `--headroom-db`, and `--auto-headroom` are mutually exclusive in the
bounded render tool. `--auto-headroom` needs an already rendered
`MixerRenderBlock` so it can inspect the pre-export Float32 peak. Export
diagnostics can report pre-export peak/RMS/overrange, post-gain
peak/RMS/overrange, PCM16 clipping, and the computed export gain/headroom.

This is a different lifecycle from live playback. Export is an explicit
offline operation where waiting for analysis is expected and the output is a
file artifact. Runtime playback is an interactive composition path where
opening a module and pressing Play should not silently perform full-song gain
analysis or change loudness per module.

## Runtime Versus Export Boundary

Runtime playback should not silently behave like offline `--auto-headroom`.
Doing so would raise unresolved product and engineering questions:

- Playback loudness could change between modules without a visible user action.
- First Play could block on analysis, or later playback could change after
  background analysis completes.
- Editing would need explicit invalidation and cache policy before the app can
  safely trust a module-specific gain result.
- A gain adjustment could hide clipping/overrange evidence that runtime
  diagnostics are meant to expose.

Offline export can afford rendered-block peak analysis because the user asked
for a bounded render/export and expects export-specific level choices. Runtime
playback should remain fast and stable unless a future UI-visible policy
changes that contract deliberately.

## Local Corpus Evidence

The adjacent-jump diagnostics clarification PR ran a local, anonymized private
corpus subset under the fixed runtime headroom policy. Raw local outputs stayed
outside the repository. The public-safe summary used labels only:

| Label | Peak | RMS | Clip | Overrange | Disc | Adj > 0.25 | Max Jump | Continuity | Level | Note |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- | --- |
| xm-corpus-001 | 0.194 | 0.026 | 0 | 0 | 0 | 0 | 0.054 | clean | clean | informational |
| xm-corpus-002 | 0.613 | 0.159 | 0 | 0 | 0 | 0 | 0.242 | clean | clean | informational |
| xm-corpus-006 | 0.564 | 0.093 | 0 | 0 | 0 | 2102 | 0.437 | watch | clean | transient watch |
| xm-corpus-010 | 0.464 | 0.094 | 0 | 0 | 0 | 0 | 0.220 | clean | clean | informational |
| xm-corpus-011 | 0.629 | 0.123 | 0 | 0 | 0 | 0 | 0.065 | clean | clean | informational |
| xm-corpus-020 | 0.999 | 0.218 | 0 | 0 | 0 | 156 | 0.310 | watch | clean | transient watch |
| xm-corpus-021 | 0.379 | 0.058 | 0 | 0 | 0 | 0 | 0.132 | clean | clean | informational |
| xm-corpus-023 | 0.491 | 0.096 | 0 | 0 | 0 | 372 | 0.444 | watch | clean | transient watch |

All sampled labels reported zero clipping, zero overrange, and zero stricter
discontinuities under the fixed runtime policy. One sampled label approached
full scale with a peak of `0.999`, but it still reported zero clipping and zero
overrange. The jump-heavy labels had `continuity_status=watch` because of
adjacent-sample jump telemetry, not because of output-level failure.

This evidence does not justify an emergency runtime gain/headroom behavior
change. It supports keeping fixed runtime headroom for now while continuing to
use runtime metrics and listening for audio-affecting PRs.

Private corpus diagnostics remain local-only evidence. Do not commit private
modules, label maps, raw logs, traces, reports, WAVs, screenshots, filenames,
titles, or local paths. Public summaries must use anonymized labels and
aggregate numbers only.

## Recommended Runtime Policy

For current VoodooTracker X runtime playback:

- Keep fixed runtime headroom as the default.
- Keep runtime auto-headroom disabled and unimplemented.
- Keep environment gain/headroom overrides as developer diagnostics only.
- Use runtime metrics to identify clipping and overrange risks.
- Treat adjacent-jump watch telemetry separately from output-level concerns.
- Do not silently alter runtime gain in response to diagnostics.
- Keep export/mastering gain decisions in the offline export layer.

Any future user-facing gain or amplification control should be designed as an
explicit playback feature, not as an implicit diagnostic side effect.

## Future Runtime Auto-Headroom Requirements

If VoodooTracker X ever adds runtime auto-headroom, it needs a dedicated design
and implementation PR. At minimum, that design must answer:

- Is runtime auto-headroom opt-in or default?
- Is the computed gain per module, per playback session, per output device, or
  only per export?
- Does it intentionally change loudness between modules?
- What cache key owns the result?
- What edit-generation, module-content, adapter-plan, sample-rate, order-list,
  pattern, instrument, sample, effect, and output-policy changes invalidate it?
- Does analysis run after load, during adapter-plan prewarm, on Play, or in a
  background task?
- What happens when analysis is incomplete or stale?
- How does it interact with explicit user gain/amplification controls?
- How does it avoid blocking file load, UI work, and the realtime audio path?
- How does it avoid changing loudness unexpectedly while a user is composing?

Future runtime auto-headroom must be cache-aware, edit-aware, and visible to
users or clearly documented. It must not run inside the realtime audio
callback, and it must not bypass `RuntimeCMixerAdapterEventPlan`.

## Pattern-Loop Implications

Headroom policy does not unlock pattern-loop playback by itself. Pattern-loop
playback is a transport/scheduler problem:

- It must preserve adapter-safe planning and not bypass the runtime adapter
  plan lifecycle.
- It must define loop transport at a safe scheduler boundary.
- It must preserve active voice, effect, envelope, sample-loop, and ramp state.
- It must pass runtime metrics and human listening gates.

If future pattern-loop work changes output level or peak behavior, runtime
metrics should catch clipping and overrange concerns. Headroom policy alone
does not make a loop boundary musically or technically continuous.

## TIME Implications

Loaded-module TIME is a composition cue derived from adapter-plan duration. It
is not a playback loudness or headroom calculation. Gain/headroom policy should
not affect whether TIME is available, and TIME work must not introduce
rendering or scanning just to compute output level.

## Visualizer Implications

Output meter visualizations may use safe snapshots of runtime output metrics
such as peak, RMS, clipping, and overrange. Tracker-style scopes, channel
meters, and note/voice visualizations need different data sources such as
per-channel or per-voice state.

Visualizers must not drive gain/headroom policy, and they must not do AppKit,
allocation, logging, file I/O, or other unsafe work in the realtime audio
callback.

## Merge-Gate Guidance

For future audio and playback PRs:

- `clipping_sample_count > 0`, `overrange_sample_count > 0`, or
  `clipping_detected=true`: investigate output level and runtime
  gain/headroom implications.
- `output_discontinuity_count > 0`: investigate possible click/pop continuity
  risk with focused listening and, when useful, capture/render comparison.
- Adjacent jumps alone: treat as watch/listen telemetry, not automatic
  failure.
- Human listening remains required for audio-affecting PRs.
- Local corpus diagnostics are evidence, not committed test fixtures.

Metrics are useful gates, but they are not a replacement for listening when a
PR changes audio behavior.

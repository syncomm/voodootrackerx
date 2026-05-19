# ADR 007: Feature-Flagged Runtime C Mixer Backend

## Status

Accepted. Initial implementation skeleton landed behind the developer-only
feature flag; the backend remains experimental and opt-in.

## Context

Default runtime playback currently remains on `AVAudioPlayerNode` and
`AVAudioUnitVarispeed`. That backend enabled stable first audible playback,
transport smoke testing, and tracker-follow integration, but it cannot own the
sample-accurate tracker rendering timeline needed for long-term playback
parity.

ADR 004 accepted moving toward a deterministic pull-based software mixer behind
the existing playback boundary while keeping the AVAudioPlayerNode backend
available until the replacement proves itself. ADR 005 clarified the language
boundary: Swift owns UI, orchestration, diagnostics, adapter/scheduling, and
tests, while the C-compatible core owns the narrow hot-path mixer/DSP boundary.

The C-backed mixer has matured through offline validation. Developer-only
bounded renders now support meaningful local candidate WAV exports, windowed
rendering, window carryover, calculated bounded song-end duration with optional
tail, auto-headroom, progress output, diagnostics JSON, and many bounded
adapter timing, volume, envelope, loop, and effect behaviors. Offline local
comparison remains the validation path for explaining remaining differences
before live playback risk is expanded.

A runtime experiment is now useful for A/B listening, transport integration,
and future tracker-follow alignment. The switch still carries real-time audio
risk and must remain opt-in, reversible, and clearly experimental.

## Decision

Use a feature-flagged runtime C mixer backend experiment without making it the
default backend.

The runtime C mixer backend must:

- Keep `AVAudioPlayerNode` / `AVAudioUnitVarispeed` as the default runtime
  backend.
- Be opt-in only.
- Be easy to disable and safe to bypass during development.
- Use Swift for transport orchestration, backend selection, diagnostics, and UI
  integration.
- Keep the C mixer as a narrow render engine.
- Reuse the same `PlaybackSong` adapter and mixer path as the offline renderer
  where practical.
- Avoid removing, weakening, or hiding the existing AVAudio backend.
- Avoid becoming the runtime default until later parity and stability gates are
  met.

The implementation branch follows this ADR by adding backend selection,
`VTX_AUDIO_BACKEND=c_mixer`, and an `AVAudioSourceNode`-hosted C mixer source
while keeping the AVAudio backend as the default. It does not add UI
preferences, parser changes, tracker viewport changes, new XM effects, or
parity claims.

## Feature Flag Proposal

The recommended initial flag is:

```text
VTX_AUDIO_BACKEND=c_mixer
```

Unset or unknown values should continue to use the existing AVAudioPlayerNode
backend. This name leaves room for additional backend names later without
creating one environment variable per backend.

An alternative flag such as `VTX_ENABLE_C_MIXER_RUNTIME=1` is acceptable if the
implementation PR needs a simpler boolean gate, but it should remain internal
and developer-facing. The first runtime experiment should not add a user-facing
preference or menu item.

## Runtime Hosting Recommendation

Prefer an `AVAudioEngine`-hosted pull source, such as `AVAudioSourceNode` or an
equivalent AVAudioEngine-compatible render source, for the first runtime C
mixer experiment. Do not jump directly to raw CoreAudio unless the
AVAudioEngine-hosted approach proves insufficient.

The expected accuracy improvement comes from owning the mixer timeline,
sample-step progression, voice state, and adapter scheduling. It does not come
from raw CoreAudio by itself. Raw CoreAudio can remain a later option if
latency, buffer-size behavior, performance, or control requirements justify the
extra surface area.

## Initial Implementation Scope

The first implementation PR should stay small:

- Add a backend-selection abstraction only if needed.
- Keep the AVAudio backend as the default path.
- Add the runtime C mixer backend behind the environment flag.
- Support basic Play/Stop smoke behavior.
- Render from the existing `PlaybackSong` adapter and C mixer path where
  practical.
- Emit clear diagnostics that the runtime C mixer path is experimental.
- Avoid tracker viewport changes.
- Avoid parser refactors.
- Avoid broad UX, menu, or preferences changes.
- Keep the existing runtime path intact.

Tracker-follow alignment may need additional work after the backend can play.
The UI should eventually follow the C mixer's sample/frame timeline, but the
initial runtime backend PR does not need to fully solve that problem. Any
tracker-follow changes should be separately scoped and should protect the
current viewport behavior.

## Real-Time Safety

The runtime render path must treat the audio callback as real-time-sensitive:

- Do not do allocation-heavy work in the render callback.
- Do not call AppKit from the audio render path.
- Do not pass parser objects into the C hot path.
- Do not depend on a broad Swift object graph inside the callback.
- Precompute and hand off state explicitly where possible.
- Keep diagnostics off the blocking render path.
- Prefer bounded, deterministic buffers and state transitions.

## Default-Backend Gates

The C mixer must not become the default runtime backend until future work can
show:

- Local/private module smoke renders are stable.
- Reference comparison workflows can explain remaining differences.
- Play/Stop runtime smoke is stable.
- There are no catastrophic stuck voices, runaway levels, or clipping failures.
- Tracker-follow behavior is acceptable or separately tracked.
- The AVAudio backend remains available as a fallback.
- CI, build, and tests remain stable.
- Manual A/B listening confirms the C backend is better or at least useful for
  development.

## Non-Goals

- Switch default playback.
- Remove `AVAudioPlayerNode` or `AVAudioUnitVarispeed`.
- Add user-facing preferences or UI.
- Change tracker viewport behavior.
- Refactor parser architecture.
- Implement remaining XM effects.
- Claim full FT2/OpenMPT parity.

## Consequences

Positive consequences:

- Creates a clear implementation plan before touching runtime audio code.
- Reduces the chance of an accidental runtime backend switch.
- Enables controlled A/B listening in a later PR.
- Preserves the stable AVAudio backend fallback.
- Keeps real-time audio risk explicit.

Risks:

- Runtime callback safety issues.
- Drift between offline and runtime paths.
- Tracker-follow alignment complexity.
- Latency and buffer-size behavior differences.
- Debugging live audio artifacts can be harder than offline WAV comparison.
- The implementation PR may be tempted to broaden into UI, parser, or viewport
  work.

Mitigations:

- Keep the runtime C mixer feature-flagged and opt-in.
- Keep the AVAudio backend as default.
- Keep the implementation PR small.
- Use manual Play/Stop and A/B smoke checklists.
- Avoid viewport changes in the backend PR.
- Avoid parser changes in the backend PR.
- Keep offline candidate rendering and comparison as the source of truth for
  diagnosing mixer differences.

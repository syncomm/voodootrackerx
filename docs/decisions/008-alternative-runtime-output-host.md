# ADR 008: Alternative Runtime Output Host for C Mixer

## Status

Accepted as opt-in experiment guidance. The implementation branch follows this
ADR with `VTX_AUDIO_BACKEND=c_mixer_coreaudio`, using a minimal CoreAudio
DefaultOutput Audio Unit host while keeping the default AVAudio backend and the
existing `VTX_AUDIO_BACKEND=c_mixer` SourceNode backend available.

## Context

The deterministic C mixer has become the authoritative path for offline export
and local render comparison. Recent runtime work has also narrowed the live
playback problem:

- Offline C mixer WAV renders can sound clean.
- Runtime C mixer source captures can sound clean.
- The AVAudioSourceNode output-copy verifier can show that the source-node
  buffer matches the captured PCM.
- Runtime sample rates have been aligned with the AVAudio graph/device where
  practical.
- Callback diagnostics have been moved toward fixed-capacity, real-time-safer
  reporting.

Despite that, live GUI playback through the experimental
`AVAudioSourceNode`-hosted C mixer path can still produce intermittent
pops/clicks that are not present in the captured WAV. That makes the current
host suspect as a delivery path, even though it does not prove that
AVAudioSourceNode is the root cause.

Main-mixer tap diagnostics were considered, but they would add another AVAudio
callback/synchronization path and are not a clear fix by themselves. A lower
level output-host experiment is a cleaner next architectural question because
classic tracker engines and MikMod-style playback models are closer to a direct
AudioUnit/CoreAudio render callback than to an AVAudioEngine source-node graph.

## Decision

Keep the existing runtime backend choices in place:

- `AVAudioPlayerNode` / `AVAudioUnitVarispeed` remains the default runtime
  backend.
- The `AVAudioSourceNode` C mixer backend remains experimental and opt-in
  through `VTX_AUDIO_BACKEND=c_mixer`.
- Existing backends must not be removed or weakened by this decision.
- Offline C mixer rendering remains the authoritative export/render path.

Plan an opt-in alternative output host experiment for the C mixer, using a
small CoreAudio/AUAudioUnit-style output callback where practical. The experiment should
answer one narrow question: whether the remaining live-only artifact is caused
by AVAudioEngine/AVAudioSourceNode delivery rather than by the C mixer PCM,
adapter event stream, sample-rate policy, or callback-side diagnostics.

## Experiment Shape

The future spike should be small, reversible, and developer-facing only.

Recommended boundaries:

- Use the same C mixer render core and planned adapter event stream as the
  current experimental runtime C mixer path.
- Select the alternative host with a new opt-in backend name or equivalent
  local diagnostic flag; unset or unknown values must keep the default AVAudio
  backend.
- Avoid a user-facing setting or menu item.
- Keep the current `AVAudioSourceNode` C mixer backend available for A/B
  comparison.
- Capture and summarize the PCM handed to the alternative host using the same
  local-only artifact rules as existing runtime captures.
- Report host callback timing, requested frame counts, underrun/zero-fill
  evidence, sample rate, channel count, and route/device context where practical.
- Prefer a minimal AUAudioUnit/CoreAudio-style render-callback host before any
  broad audio-engine rewrite.

The implementation PR may choose the concrete API after a focused prototype.
The important architecture constraint is that the C mixer owns PCM generation
and scheduling while the host experiment changes only the runtime delivery
surface.

## Validation Questions

The spike should produce evidence for these outcomes:

- If offline C mixer WAVs, runtime handoff captures, and the alternative host's
  handoff PCM are clean while live output becomes clean, the current
  AVAudioSourceNode/AVAudioEngine delivery path becomes the leading suspect.
- If the alternative host still clicks while its handoff PCM remains clean, the
  investigation should move toward route/device/hardware behavior or other
  downstream delivery conditions.
- If the alternative host handoff PCM is dirty, the bug is not downstream of
  the C mixer handoff and the runtime mixer/event path must be revisited.

Any comparison evidence must use local-only WAVs, traces, logs, and listening
notes kept outside git.

## Non-Goals

This ADR and its initial implementation do not:

- switch the default runtime backend
- remove the `AVAudioPlayerNode` / `AVAudioUnitVarispeed` backend
- remove the experimental `AVAudioSourceNode` C mixer backend
- change offline render behavior
- change C mixer DSP semantics
- add tracker viewport changes
- add parser changes
- add new XM effects

## Consequences

Positive:

- records the current evidence that the remaining artifact is live-host
  specific, not currently explained by offline PCM or source-node capture PCM
- gives the next runtime stabilization PR a narrow question and reversible
  scope
- preserves the stable default runtime backend and the existing SourceNode A/B
  path
- keeps offline C mixer export/render behavior authoritative

Tradeoffs:

- a lower-level host increases runtime surface area and real-time safety risk
- duplicated runtime host plumbing must stay temporary until evidence justifies
  keeping it
- success would still require a later decision before any default backend
  change

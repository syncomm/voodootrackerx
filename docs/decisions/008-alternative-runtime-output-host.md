# ADR 008: Alternative Runtime Output Host for C Mixer

## Status

Accepted. Superseded in implementation by the runtime-host retirement pass:
`VTX_AUDIO_BACKEND=c_mixer` and `VTX_AUDIO_BACKEND=c_mixer_coreaudio` now both
select the minimal CoreAudio DefaultOutput Audio Unit host. The default
`AVAudioPlayerNode` / `AVAudioUnitVarispeed` backend remains unchanged, and the
AVAudioSourceNode-hosted C mixer backend is retired.

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
`AVAudioSourceNode`-hosted C mixer path produced intermittent pops/clicks that
were not present in the captured WAV. That made the host suspect as a delivery
path, even though it did not prove that AVAudioSourceNode was the root cause.

Main-mixer tap diagnostics were considered, but they would add another AVAudio
callback/synchronization path and are not a clear fix by themselves. A lower
level output-host experiment is a cleaner next architectural question because
classic tracker engines and MikMod-style playback models are closer to a direct
AudioUnit/CoreAudio render callback than to an AVAudioEngine source-node graph.

## Decision

Retire the AVAudioSourceNode-hosted runtime C mixer backend and keep the
runtime backend choices small:

- `AVAudioPlayerNode` / `AVAudioUnitVarispeed` remains the default runtime
  backend.
- `VTX_AUDIO_BACKEND=c_mixer` selects the experimental CoreAudio DefaultOutput
  Audio Unit C mixer host.
- `VTX_AUDIO_BACKEND=c_mixer_coreaudio` remains accepted as an alias for the
  same CoreAudio host.
- The AVAudioSourceNode C mixer host is no longer selectable.
- Offline C mixer rendering remains the authoritative export/render path.

The CoreAudio host is still experimental and developer-facing only. This
decision reduces duplicated runtime host plumbing and keeps future hardening
focused on one C mixer delivery surface.

## Experiment Shape

The CoreAudio host remains small, reversible, and developer-facing only.

Boundaries:

- Use the same C mixer render core and planned adapter event stream as the
  previous experimental runtime C mixer path.
- Select it only through the accepted developer backend names; unset or unknown
  values must keep the default AVAudio backend.
- Avoid a user-facing setting or menu item.
- Capture and summarize the PCM handed to the CoreAudio host using the same
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

- If offline C mixer WAVs, runtime handoff captures, and the CoreAudio host's
  handoff PCM are clean while live output becomes clean, the retired
  AVAudioSourceNode/AVAudioEngine delivery path remains the leading historical
  suspect.
- If the CoreAudio host still clicks while its handoff PCM remains clean, the
  investigation should move toward route/device/hardware behavior or other
  downstream delivery conditions.
- If the CoreAudio host handoff PCM is dirty, the bug is not downstream of
  the C mixer handoff and the runtime mixer/event path must be revisited.

Any comparison evidence must use local-only WAVs, traces, logs, and listening
notes kept outside git.

## Non-Goals

This ADR and its initial implementation do not:

- switch the default runtime backend
- remove the `AVAudioPlayerNode` / `AVAudioUnitVarispeed` backend
- change offline render behavior
- change C mixer DSP semantics
- add tracker viewport changes
- add parser changes
- add new XM effects

## Consequences

Positive:

- records the current evidence that the remaining artifact is live-host
  specific, not currently explained by offline PCM or runtime handoff capture
  PCM
- gives the next runtime stabilization PR one runtime C mixer host to harden
- preserves the stable default runtime backend
- keeps offline C mixer export/render behavior authoritative

Tradeoffs:

- a lower-level host increases runtime surface area and real-time safety risk
- the previous SourceNode A/B path is no longer available
- success would still require a later decision before any default backend
  change

# VoodooTracker X — Development Roadmap

This document is the lightweight, phase-based roadmap.

Primary roadmap:
- Use `docs/roadmap.md` for the detailed PR-by-PR plan and current sequencing.

Use this file when you want a short phase summary rather than the full implementation roadmap.

---

# Current State Snapshot

VoodooTracker X has moved beyond the original parser and early pattern-editor
baseline. The current app has a working AppKit tracker shell, module open/load
flow, tracker-style pattern display, static highlight row behavior, stable
viewport navigation, first-pass XM playback, playback diagnostics, and an
initial deterministic software mixer skeleton.

Default runtime playback now uses the CoreAudio DefaultOutput Audio Unit C
mixer backend. `VTX_AUDIO_BACKEND=c_mixer` and
`VTX_AUDIO_BACKEND=c_mixer_coreaudio` remain accepted aliases for the same
CoreAudio host, while `VTX_AUDIO_BACKEND=av_audio` is a retired legacy value
that falls back to that CoreAudio host with `fallbackReason=retired_backend`.
Unknown backend values fall back to the CoreAudio default and are reported in
diagnostics. The retired AVAudioSourceNode C mixer host is no longer selectable. The software mixer path is
groundwork for offline rendering and future reference comparison; it can render
synthetic one-shot sample voices plus
synthetic forward and ping-pong loops, volume/panning envelope foundations,
absolute-frame, row/tick scheduled, minimal synthetic pattern voices, and tiny
bounded `PlaybackSong` adapter segments through the offline harness with
source-to-synthetic diagnostics. The CoreAudio runtime C mixer render core now
keeps the normal callback path to one non-blocking render/copy/counter entry
with fixed-capacity callback diagnostics, and the first CoreAudio host
hardening/corpus pass now uses summary-backed callback, route, lifecycle, and
capture health evidence while keeping the default switch as a separate future
decision. Those bounded candidate renders can now be written as deterministic
PCM16 WAV files for local comparison. Parsed
`PlaybackInstrument.volumeEnvelope` points can be converted into the C-backed
frame-based envelope representation for those bounded offline adapted renders
only, with first-pass sustain, envelope loop, note value `97` key-off release,
and post-key-off fadeout semantics now represented in that offline path. Adapted
note triggers carry explicit XM linear-frequency period/frequency
sample-step mapping where `PlaybackSong.usesLinearFrequencyTable` is true, and
the adapter applies volume-column set-volume/set-panning plus a conservative
row-level subset of volume-column volume and panning slides to event gain/pan.
It also applies minimal bounded/offline state updates for empty-note and
same-cell `3xx` no-retrigger volume-column set-volume/set-panning cells,
regular effect-column `Cxx` set volume, regular effect-column `8xx` set
panning, and nonzero tick-level `Axy` volume slides after tick 0; where a
carried voice is active, deterministic gain/pan update events can update that
voice after its original note trigger, and changed active-voice gain/pan
updates are smoothed by a fixed 32-frame C mixer micro-ramp in the
bounded/offline path. Minimal
row-level `Hxy` global volume slide is also applied in the bounded/offline
adapter: the adapter carries a
clamped `0...64` global-volume value, defaults to `64`, applies up/down Hxy
slides once at the source row, updates active voices through the same generic
gain-update path, and uses that multiplier for later note triggers. `H00` is
diagnosed as a no-op without effect memory, and both-nibble Hxy parameters use a
diagnosed up-nibble-precedence policy. The bounded adapter also applies
minimal `Fxx` timing changes for offline renders only: `F01...F1F` updates
speed, `F20...FFF` as byte parameters updates BPM, and `F00` is diagnosed as an
ignored no-op. It also applies minimal `9xx` sample offsets to same-cell
note/sample triggers, replays per-channel `900` memory when prior nonzero
`9xx` memory exists, diagnoses unavailable `900` memory as
ignored/deferred/no-op, and skips out-of-range offsets safely. Minimal `ECx`
note cut and `EDx` note delay are supported in bounded offline renders only;
`ECx` hard-cuts the active adapted voice at the requested tick and `EDx` delays
only normal same-cell note triggers. Minimal `1xx`/`2xx` portamento up/down and
minimal `3xx` tone portamento are supported in bounded offline renders only:
`1xx`/`2xx` slide the tracked active voice's linear-period/sample-step on later
row ticks, and `100`/`200` replay prior nonzero same-family per-channel memory
when available. A normal-note `3xx` sets a linear-frequency target for the
active voice without retriggering the sample; when the same cell also carries
an instrument, the bounded/runtime adapter updates instrument/sample/default
volume state and active-voice gain before later ticks schedule deterministic C
mixer sample-step updates toward the target. No-active,
missing-memory, no-target, no-speed, clamped, and non-linear pitch-table cases
are diagnosed as applicable, while `5xy` and volume-column tone portamento
remain deferred.
Minimal `E1x` fine portamento up and `E2x` fine portamento down now use the
same runtime/offline linear-frequency sample-step update path for one
deterministic row-level pitch adjustment. Same-cell notes fold the adjustment
into the note's initial playback step, no-note rows update the active voice at
row start, and `E10`/`E20` remain effect-memory-deferred no-ops. Minimal `4xy`
vibrato now uses the same linear-frequency sample-step update foundation in the
runtime/offline C mixer adapter path, with deterministic row-tick modulation
diagnostics for speed/depth, E4x-selected sine/ramp/square/deterministic-random
waveform state, active voice updates, no-active-voice,
`400`/single-zero-nibble memory replay, and effect-memory-deferred no-ops when
required memory is unavailable. Minimal `E4x` vibrato control stores
per-channel waveform/control state for later `4xy`/`6xy` rows without emitting
direct audio events; unsupported control values remain explicit deferred
diagnostics. Minimal `EAx`/`EBx` fine volume slides now
apply one deterministic row-level clamped channel-volume adjustment through the
shared runtime/offline gain-update path. Same-cell notes trigger with the
adjusted volume, no-note rows update an active voice at row start, and
`EA0`/`EB0` remain effect-memory-deferred no-ops. Minimal `6xy` vibrato +
volume slide now reuses prior channel vibrato memory for sample-step updates and
the existing row-level gain path for nonzero volume slides; `600`
can replay vibrato memory without broad volume-slide memory, while missing
vibrato memory, volume-column vibrato, and unrelated effect-memory families
remain deferred.
Minimal `E9x` retrigger is also supported
in bounded offline renders only; it schedules same-channel retrigger starts at
the row's effective tick frames, preserves the tracked active voice's sample,
offset, pitch, volume, pan, loop, and envelope mapping, and diagnoses `E90`,
no-active-voice, and out-of-row cases without effect memory. Fractional
C-backed offline sample steps now have microfixture coverage for deterministic
linear interpolation, double-precision sample positions/steps, safe no-loop
ends, forward-loop wraps, and ping-pong turnarounds, with bounded render
diagnostics reporting the interpolation and sample-step precision modes. The
focused loop-endpoint correctness-hardening pass confirmed that XM loop starts
plus lengths map to exclusive C mixer loop ends, and it now normalizes imported
forward-loop runtime positions at or beyond the exclusive end while preserving
fractional overshoot. Exact initial source offsets at the exclusive end also
start at the loop start; offsets after the loop end retain the existing
tail-read behavior. The local anonymized loop-heavy and envelope-heavy
validation renders were byte-identical before and after this endpoint fix. This
did not improve the observed local reference mismatch, so the remaining
private-corpus mismatch is not explained by this exact boundary condition. The
period/sample-step conversion investigation added windowed active-voice pitch
summaries to the local correlation report and reviewed the current XM linear
period pipeline, including effective note, relative note, finetune, fixed
sample base rate, output sample rate, tone-portamento targets, and scheduled
sample-step update timing. The primary loop-heavy envelope-disabled local target
still looks compatible with a pitch/phase/loop-speed class of mismatch, but no
tiny formula or C-side stepping bug was proven. The secondary envelope-heavy
target remains strongly confounded by envelope/key-off/fadeout evidence. The
follow-up linear-period/sample-rate parity audit confirmed the FT2 linear
period/frequency equations and fixed 8363 Hz C-4 base-frequency anchor, and
fixed relative-note clamping to XM's zero-based real-note range `0...118`
instead of pattern note values `1...96`. The inspected loop-heavy mismatch
windows did not contain out-of-range relative-note cases, so no local
reference-correlation improvement was attributed to that fix. The strongest
next parity target was investigated with envelope/key-off/fadeout timing
diagnostics: bounded JSON now exposes mapped envelope points plus start/key-off
snapshots, and the local correlation report estimates per-window envelope
position/value/segment, sustain-hold, loop-active, key-on, fadeout, final-gain,
and audible-envelope counts when those optional fields are present. Local
Renoise comparison against `xm-corpus-011` still shows broad late-song
mismatch windows with envelope/key-off/fadeout metadata present and 66...82
audible envelope-enabled voices in the top windows, mostly sustain-held with
fadeout still at 1.0. The `xm-corpus-025` control windows remain
envelope-disabled with zero key-off evidence. No tiny behavior bug was proven,
so the next implementation target should be a narrowly tested volume-envelope
tick-clock/sustain timing policy pass, with key-off/fadeout scaling and
gain/panning math kept as separate follow-ups if expected-value tests isolate
them. Bounded offline note
triggers now use parsed XM instrument sample maps/keymaps when a valid
multi-sample mapping is present,
with diagnostics for sample-map selection, first-playable fallback,
fallback-after-invalid-map, skipped-no-valid-sample, and missing/deferred
keymap state. Amiga-table pitch behavior, full
OpenMPT/MikMod resampler parity, broader pitch-changing effects, full XM volume-column
parity, and full effect parity remain deferred. The path does not yet render
full XM song playback or drive live playback. Local/private XM bounded comparison findings
now have a safe report template and local-only workflow guidance, and a
developer-only `vtx_render_bounded_xm` helper can render bounded candidate WAVs
from local XM files through the existing offline export path. The helper can
optionally export local bounded adapter diagnostics JSON, and a local
correlation script can map audio comparison mismatch windows to approximate
bounded adapter rows/events and summarize applied, ignored/no-op,
deferred/unsupported, and unknown effect-column, volume-column, and
volume/panning state-update command frequency for focused follow-up diagnosis.
It now also reports applied `0xy` arpeggio diagnostics, applied `1xx`/`2xx`
portamento-slide diagnostics, applied `3xx` tone-portamento diagnostics,
applied `E1x`/`E2x` fine-portamento diagnostics, applied `EAx`/`EBx`
fine-volume-slide diagnostics, applied `4xy` vibrato diagnostics, applied
`6xy` vibrato + volume slide diagnostics, explicit
effect-memory reused/missing counts and source metadata for
`900`/`1xx`/`2xx`/`4xy`/`6xy`,
and deferred pitch-modulation counts and source coordinates for remaining
portamento-family commands, tremolo, and volume-column
vibrato/tone-portamento commands, with a conservative
pitch-effect next-PR recommendation when one bucket dominates local evidence.
Bounded diagnostics also count
pattern traversal and timing hazards such as `Bxx` position jump, `Dxx` pattern
break, `E6x` pattern loop, `EEx` pattern delay, contextual `Fxx`, and other
observed `E` subcommands. The focused traversal foundation now applies
deterministic first-pass `Dxx`/`Bxx`/`E6x` planning in the Swift adapter/runtime
planning layer while keeping `EEx` and broader tracker traversal quirks
deferred. A local-only XM effect
coverage summary helper can now aggregate bounded offline diagnostics JSON and
runtime C mixer JSONL traces into detected/applied/deferred/unsupported/no-op
effect tables, first source coordinates, unresolved key-off/no-active buckets,
and a conservative next-effect recommendation; filled reports and generated
audio artifacts stay outside git. Reference-render parity triage summaries can
now aggregate anonymized `scripts/audio-compare.py` JSON metrics across selected
private/local modules, including scalar gain-normalized evidence and
missing-reference status, without changing playback behavior or committing
artifacts. A post-`E1x` local-only full mapped-corpus
refresh covered 26 anonymized inputs and reported 222,402 detected commands,
214,105 applied, 187 deferred, 172 unsupported, 8,125 no-op/effect-memory
deferred, 3,316 effect-memory reuses, and one missing effect-memory case. The
largest remaining unsupported buckets after the portamento-memory refresh were
`E0x` filter toggle (limited usefulness), `0xy` arpeggio (strong), and smaller
`Dxx`/`Bxx`/`E6x` traversal cases. The current 0xy arpeggio and focused
`Dxx`/`Bxx`/`E6x` traversal foundations move those concrete buckets into the
applied or explicit safe-diagnostic path; the next effect target should likely
refresh residual corpus classification and clean up `E0x` deferral reporting
unless local evidence points at a higher-value remaining bucket. A post-focused
same-cell `3xx` gain-state local-only refresh covered 26 anonymized inputs and
reported 222,392 detected commands, 215,060 applied, 96 deferred, 81
unsupported, 7,250 no-op/effect-memory-deferred, 4,174 effect-memory reuses,
and one missing effect-memory case. `E0x` filter toggle remains the largest
limited-usefulness deferral, while the clearest small concrete unsupported
bucket was `E4x` vibrato control; the focused E4x pass now stores supported
vibrato controls and leaves unsupported control values visible. Traversal and
supported effect-memory residuals are covered or explicit safe/no-active
classifications. The
developer-only helper keeps its default
60-second safety clamp, and explicit longer local candidate WAV renders now use
documented `--seconds` / `--max-frames` controls gated by
`--allow-long-render`. It can also render with `--until-song-end` plus optional
`--tail-seconds N`, computing the bounded selected order-range end from the
adapter timing model, including minimal supported `Fxx` timing changes, while
avoiding default looping and full FT2/OpenMPT song-duration parity. Bounded
adapter event-coverage diagnostics now compare
parsed normal note cells against scheduled C-backed events, report skipped-note
reasons and coordinates, expose sample-selection methods and fallbacks, and
report C mixer scheduled/active capacity values, reject counts, and rejected
event coordinates without changing runtime playback. Long developer-only
candidate WAV exports can now opt into `--window-rows` row-windowed offline
scheduling to reuse the fixed C scheduled-voice pool across deterministic
render windows, with aggregate/per-window capacity and carryover diagnostics.
Windowed renders now carry practical active voice state across fresh C mixer
windows where the bounded adapter can determine it, including source sample
position, forward/ping-pong loop state, volume-envelope position,
key-off/release, fadeout, gain, pan, and active `1xx`/`2xx`/`3xx`, `E1x`,
`E2x`, `4xy`, `6xy`, and supported sample-offset memory state, plus supported in-window
`EAx`/`EBx` and `6xy` gain updates.
Unsupported/deferred effects and full tracker voice semantics remain separate
targeted work. Developer-only bounded candidate WAV exports now also report
Float32 output headroom/clipping diagnostics and can apply explicit `--gain` or
`--headroom-db` before PCM16
conversion without changing runtime playback, C mixer DSP semantics, or the
default output gain. Local/offline click/discontinuity diagnostics can now
analyze candidate WAV adjacent-sample jumps and optionally correlate top jumps
with bounded adapter diagnostics such as gain/pan updates, retriggers, note
cuts/delays, note triggers, looped/carryover/window events, and
key-off/fadeout evidence.
The bounded/offline C mixer now reports gain/pan ramp settings and counts in
diagnostics. ADR 007's feature-flagged runtime C mixer plan started as an
opt-in implementation skeleton, kept the AVAudio backend available, used an
AVAudioEngine-hosted pull source initially, and kept tracker viewport, parser,
and broad UI work out of the backend PR. Runtime C
mixer A/B listening diagnostics now add a local-only JSONL trace for backend
selection, PlaybackEngine order/row/tick context, note/key/stop events, C mixer
add/clear/stop calls, render-frame counters, and channel-scoped stop/replacement
evidence. The runtime C mixer now tags runtime voices by caller-owned
channel id so immediate channel stops use `c_mixer_stop_channel` instead of
clearing all C mixer voices. Same-channel runtime note replacement now uses a
deterministic 32-frame replacement stop ramp, emits
`c_mixer_stop_channel_ramped`, and lets the new replacement voice start while
the old tagged voice fades out briefly. True transport stop/reset still clears the
runtime C mixer globally. Runtime C mixer output diagnostics now extend that
local-only trace with render callback counters, requested/rendered frame counts,
zero-fill/underrun evidence where detected, output peak/RMS and
clipping/overrange summaries, row-transition snapshots, backend lifecycle breadcrumbs,
and explicit runtime headroom policy reporting. The runtime C
mixer now applies a conservative runtime-only output gain/headroom policy at the
runtime C mixer handoff, defaults to `-12 dB`, reports post-gain clipping
diagnostics and recommendations, and accepts local-only gain/headroom
environment overrides when the runtime C mixer backend is active. Offline
export `--auto-headroom` remains separate, and `VTX_AUDIO_BACKEND=av_audio`
falls back to the CoreAudio C mixer. The runtime C mixer now bridges supported
runtime gain/pan/sample-step control updates to the same generic C mixer
voice-state update primitives used by the bounded offline path, including the
fixed gain/pan micro-ramp and channel-scoped target voice diagnostics. Missing
target, no-change, stale-after-stop, missing-data, and unsupported update cases
are now classified separately. No-change runtime refreshes are suppressed,
gain/pan updates without an active voice can be retained as channel state for a
later note trigger, and step/pitch updates without an active sample/note target
remain explicit no-active or missing-data deferrals. The runtime bridge also
filters gain, pan, and sample-step update deltas at a strict `1e-5` epsilon so
tiny floating-point discrepancies do not restart C mixer ramps or step updates.
This reduced trace noise around the remaining update deferrals without changing
runtime adapter semantics.
Runtime C mixer stabilization diagnostics now add a local trace summary helper
for CoreAudio runtime diagnostics. It reports output health counters, stop/replacement
paths, immediate hard stops, clear-all evidence, active/loaded voice ranges,
applied/suppressed/stored/deferred update categories, and event bursts from
runtime JSONL traces. The runtime C mixer now precomputes a
runtime adapter event plan from the bounded/offline `PlaybackSong` adapter and
feeds supported plan events to the C mixer backend when available. Trace
rows report the event source, plan generation, planned/consumed/skipped counts,
adapter event categories, row/order mapping, and fallback-to-simple-runtime
counts. `c_mixer` remains an explicit CoreAudio alias, `av_audio` remains only
as a retired value that falls back to CoreAudio, and unsupported XM effects
remain unsupported. Runtime
sample-time event application now queues planned adapter events by intended
runtime frame, splits runtime host callbacks at in-buffer event offsets,
and traces callback ranges, planned/applied frames, offsets, same-frame burst
sizes, exact-frame/callback-boundary/late counts, and max planned-vs-applied
deltas. Runtime sample-time position diagnostics now resolve the C mixer frame
cursor back to the planned adapter order/pattern/row/tick timeline and compare
that with the `PlaybackEngine` timer position, including row-transition delta
categories, PlaybackEngine-vs-C-mixer frame/millisecond delta summaries,
constant-offset versus accumulating-drift classification, first-divergence
reporting, selected order-transition samples, and largest mismatch summaries.
The C mixer backend now uses that sample-time-derived position as the published
playback-follow position when the planned adapter timeline is available. Runtime
traces distinguish the `PlaybackEngine` timer position, the C mixer sample-time
position, and the published follow position.
Runtime transient/burst diagnostics now add lower adjacent-sample thresholds,
bounded top jumps and peaks, same-frame burst summaries with event categories and
voice counts, replacement ramp cleanup counters, epsilon-suppression correlation,
and a local-only update-epsilon override for diagnostics. These additions remain
diagnostic-only; unsupported XM effects remain unsupported, and broad
stabilization remains separate.
Runtime C mixer peak-safe headroom stabilization now makes the fixed runtime
default slightly more conservative at `-12 dB`, reports whether the active gain
policy came from the default or an environment override, and keeps peak/clipping,
lower-threshold adjacent-sample jump, and same-frame burst diagnostics visible
without altering event timing or C mixer DSP. Exact offline-style runtime
auto-headroom remains separate future work requiring a pre-playback preflight or
dry-render peak-analysis pass from the selected start position.
Runtime C mixer live output capture tooling is now available for local-only
offline-vs-live comparison: when the CoreAudio C mixer backend is active and
`VTX_C_MIXER_RUNTIME_CAPTURE_PATH` is set, the backend captures the
post-runtime-gain CoreAudio host output into a bounded in-memory buffer and
writes a local WAV outside the audio callback on stop/reset. Capture
summaries report basename-only paths, captured frames, truncation, gain policy,
peak/RMS, and clipping counters. Broader pop mitigation remains separate future
work.
Runtime C mixer event-burst and sustained-voice transition stabilization now
aligns same-frame runtime adapter event ordering with the offline C mixer frame
boundary: gain/pan and sample-step updates apply before note cuts and note
triggers, while same-channel replacement ramps remain internal to the note
trigger path. Runtime traces now report deterministic same-frame burst IDs,
event ordinals, affected channels, category counters, active/loaded voice
counts before and after, ramp-down starts/completions, new voices, sustained
carried voices, order-start/row-transition flags, and carried-channel
association fields for update-without-note cells. Broader runtime
stabilization remains separate future work.
Runtime C mixer event-burst mitigation follow-up is kept diagnostics-only after
local capture comparison showed no material runtime/offline metric improvement
from forcing same-frame state into replacement ramps. Replacement trace rows now
expose old voice state, replacement ramp start/target state, new voice id/tag
when known, and booleans for gain/pan, sample-step, key-off, and fadeout state
before ramp start. Runtime traces also report output-host and hardware
sample-rate/channel diagnostics for downstream output delivery investigation.
This did not change offline rendering
semantics, add XM effects, alter tracker viewport behavior, or change parser
architecture.
Runtime C mixer sample-rate alignment now selects the runtime C mixer sample
rate from the output graph/device where practical, configures the C
mixer/runtime-host/capture path with that selected
rate, and keeps planned adapter event frames plus sample-time resolver frames on
the same runtime timeline. The policy is traced as `graph_aligned`,
`explicit_env`, or `fallback_44100`, with `VTX_C_MIXER_RUNTIME_SAMPLE_RATE`
available only for local C-mixer diagnostics. Offline rendering defaults are
unchanged, and broader runtime stabilization remains separate.
Runtime C mixer callback/output-delivery diagnostics now add local-only
callback duration, render quantum, callback interval, output-buffer fill/copy,
and scratch/capture/output hash evidence for the CoreAudio backend. Local
flags can disable trace, capture, or both for callback-overhead isolation. This
diagnostics PR did not alter offline rendering or C mixer DSP and left any
actual output-device fix for a later scoped PR.
Runtime C mixer output-device and callback-isolation diagnostics now extend the
same trace with hashed output-device identity, optional safe route label,
hardware transport type, hardware IO/latency fields, output-host start counts,
graph/route change counts, route-change event fields, callback thread
id/main-thread status, event-queue producer/consumer thread ids, diagnostic
allocation-risk reporting, and a local-only follow-publication disable flag for
UI/callback isolation. Trace summaries also report clean-source/dirty-live
route-device versus callback candidate conclusions for local route-matrix
smokes. This remains diagnostics-only; any hardware-route fix is separate
follow-up work.
Runtime C mixer render callback diagnostics now use fixed-capacity diagnostic
buffers and counters for callback-side event summaries, over-budget/output
health counters, try-lock failures, and diagnostic drops. Trace summaries report
`callbackRealtimeSafeDiagnostics`, `callbackDiagnosticDropCount`,
`callbackRingBufferCapacity`, and `callbackLockFailureCount`, while
allocation-prone output-copy hashing is an explicit local opt-in. This leaves
offline rendering and C mixer DSP unchanged and keeps output-device/hardware
stabilization as separate work.
Runtime C mixer CoreAudio callback lock-contention follow-up now makes
try-lock failures explicit as output-delivery events: the callback does not
block, reuses the last valid callback output when available, counts stale-output
fallbacks and any unavailable-state silence separately, and reports lock
attempts, skipped diagnostics, skipped-audio protection, near-budget callbacks, and
lifecycle-overlap counters. Long-run tracker-follow and row-transition trace
breadcrumbs use callback-published sample-time frames while the host is running
so main-thread UI/diagnostic publication does not take the render lock. The
callback remains on the CoreAudio render thread.
Runtime C mixer CoreAudio default selection now makes that CoreAudio host the
default runtime backend. `VTX_AUDIO_BACKEND=av_audio` is now retired and falls
back to CoreAudio C mixer, `c_mixer` and `c_mixer_coreaudio` remain CoreAudio
aliases, and the retired AVAudioSourceNode C mixer path remains unavailable.
Runtime/offline mismatch window correlation diagnostics are available after
live capture. A local-only helper compares full
or near-full runtime capture WAVs against offline C mixer WAVs, imports
whole-song `scripts/audio-compare.py` worst windows, adds explicit target
windows, and correlates each window with runtime trace events, same-frame
bursts, sustained voice association, active/loaded voice ranges, gain/headroom
normalization, local alignment shifts, and optional offline diagnostics JSON.
This is diagnostics-only: it does not alter offline rendering, change C mixer
DSP, add XM effects, modify tracker viewport behavior, or refactor parser
architecture.
ADR 008 documents the runtime-host decision that retired the SourceNode path
after local evidence pointed to delivery-host behavior rather than offline C
mixer rendering. AVAudioPlayerNode/AVAudioUnitVarispeed was the first audible
playback backend and has since been retired. The CoreAudio DefaultOutput Audio
Unit C mixer host is now selected by default, by `VTX_AUDIO_BACKEND=c_mixer`,
and by
`VTX_AUDIO_BACKEND=c_mixer_coreaudio`. Capture duration is
reported separately from `VTX_DEBUG_STOP_AFTER_SECONDS` and planned song end, so
capture caps can be tested without treating them as playback lifetime. Runtime
C mixer song-end tail handling stops or silences the CoreAudio host at the
planned adapter song end plus a short tail; CoreAudio host hardening remains a
separate follow-up.
Transport stop-position preservation and the tracker-style plain Spacebar
play/stop shortcut are implemented for manual debugging workflow: manual Stop
preserves the current published order/row position, play resumes from the
current position, and Space toggles play/stop through the tracker grid focus
path without adding broader shortcut parity or pattern-editing behavior.

Immediate audio accuracy sequence:

1. Software Mixer Skeleton Behind AudioEngine — done
2. Offline Render Harness for Software Mixer — done
3. One-shot sample rendering — done
4. Forward and ping-pong loop rendering — done
5. Software mixer core language boundary ADR — done
6. Minimal C mixer core skeleton with Swift wrapper — done
7. Port one-shot rendering to the C-backed path — done
8. Port forward and ping-pong loop rendering to the C-backed path — done
9. C-backed volume, panning, and envelope foundations — done
10. C-backed timing and voice scheduling foundations — done
11. Synthetic tracker tick and row timing model — done
12. Minimal synthetic pattern playback through the C-backed mixer — done
13. Parsed XM-to-synthetic playback adapter planning — done
14. Minimal PlaybackSong-to-synthetic adapter, constant timing, no effects — done
15. Adapter diagnostics and bounded offline render helper — done
16. Parsed volume envelope mapping for bounded offline adapted renders — done
17. Minimal pitch foundation for bounded offline adapted renders — done
18. Local-only bounded reference render comparison workflow — done
19. Bounded C-mixer WAV export helper — done
20. Local reference comparison smoke using bounded candidate WAVs — done
21. Adapter volume-column set-volume/set-panning support for bounded offline renders — done
22. Minimal Fxx timing changes for bounded offline adapter renders — done
23. Adapter support for additional volume-column slides in bounded offline renders — done
24. Local/private bounded comparison findings workflow — done
25. Developer-only bounded XM candidate WAV render helper — done
26. Local trace-to-comparison correlation report — done
27. Deep project handoff checkpoint
28. Focused pitch/period accuracy for bounded linear-frequency renders — done
29. Interpolation/resampling foundation for C-backed offline mixer — done
30. Deferred envelope sustain/loop/key-off/fadeout semantics for bounded offline renders — done
31. Minimal sample offset 9xx for bounded offline renders — done
32. Local effect frequency report from correlated mismatch windows — done
33. Developer render duration controls for bounded XM candidate WAV helper — done
34. Bounded adapter event coverage / missing note trigger diagnostics — done
35. PlaybackSong adapter instrument sample-map/keymap support — done
36. C mixer scheduled voice capacity / diagnostics hardening — done
37. Pattern traversal / Bxx-Dxx-EEx diagnostics for bounded offline renders — done
38. Minimal bounded traversal behavior for `Bxx`/`Dxx`/`E6x` — done
39. Chunked/windowed offline render scheduling for long candidate WAV exports — done
40. Window state carryover refinement for windowed offline candidate renders — done
41. Minimal volume/panning state effects for bounded offline renders — done
42. Minimal note cut ECx / note delay EDx for bounded offline renders — done
43. Mixer output headroom / clipping diagnostics and render gain policy — done
44. Mixer click / discontinuity diagnostics for candidate WAVs — done
45. Gain / pan update micro-ramping for bounded offline renders — done
46. Minimal retrigger E9x for bounded offline renders — done
47. Portamento / Vibrato / Arpeggio Diagnostics for Bounded Offline Renders — done
48. Minimal tone portamento 3xx for bounded offline renders — done
49. Minimal portamento up/down 1xx / 2xx for bounded offline renders — done
50. Song-end duration / tail handling for vtx_render_bounded_xm — done
51. ADR: Feature-flagged runtime C mixer backend plan — done
52. Feature-flagged runtime C mixer backend skeleton — done
53. Runtime C mixer A/B listening diagnostics — done
54. Runtime C mixer per-channel voice stop / replacement semantics — done
55. Runtime C mixer output diagnostics / offline parity investigation — done
56. Runtime C mixer headroom / gain policy — done
57. Runtime C Mixer Event Scheduling / Offline Adapter Parity Bridge — done
58. Runtime C Mixer Remaining Update Deferral Fix — done
59. Runtime C Mixer Hard Stop / Replacement Micro-Ramping — done
60. Runtime C Mixer Stabilization / A-B Listening Diagnostics Pass — done
61. Runtime C Mixer Offline Adapter Event Stream Bridge — done
62. Runtime C Mixer Sample-Time Event Alignment Diagnostics — done
63. Runtime C Mixer Sample-Time Event Scheduling Bridge — done
64. Runtime C Mixer Playback Follow Position Drift Investigation — done
65. Runtime C Mixer Tracker Follow Uses Sample-Time Position — done
66. Runtime C Mixer Transient / Event-Burst Diagnostics — done
67. Runtime C Mixer Peak-Safe Headroom / Burst Transient Stabilization — done
68. Runtime C Mixer Live Output Capture / Offline WAV Comparison — done
69. Runtime C Mixer Event-Burst / Voice Transition Stabilization — done
70. Runtime / Offline Mismatch Window Correlation Diagnostics — done
71. Transport stop-position preservation / Spacebar playback shortcut — done
72. Runtime C Mixer AVAudioSourceNode Format / Device Sample-Rate Alignment — done
73. Runtime C Mixer AVAudio Callback Realtime Safety / I/O Buffer Diagnostics — done
74. Runtime C Mixer Render Callback Diagnostics Decoupling — done
75. ADR: Alternative Runtime Output Host for C Mixer — done
76. Runtime C Mixer CoreAudio/AUAudioUnit Output Host Spike — done
77. Runtime C Mixer Output Host A/B Listening and Capture Comparison — done
78. Runtime C Mixer Song-End Stop / Tail Handling — done
79. Deprecate AVAudioSourceNode C Mixer Backend / Prefer CoreAudio Experimental Host — done
80. Runtime C Mixer CoreAudio Render Core Slimdown / Realtime Boundary Hardening — done
81. Runtime C Mixer CoreAudio Host Hardening / Manual Corpus Pass — done
82. Runtime C Mixer CoreAudio Callback Lock Contention / Output Delivery Follow-Up — done
83. Runtime C Mixer CoreAudio Default / AVAudio Legacy Fallback — done
84. Remove AVAudioPlayerNode Legacy Backend — done
85. Runtime Diagnostics Cleanup / Remove Obsolete Backend Debugging — done
86. XM Effect Coverage Audit / Local Missing-Effect Target Selection — done
87. Minimal 4xy Vibrato Foundation — done
88. Minimal E5x Set Finetune Foundation — done
89. Minimal E2x Fine Portamento Down — done
90. Minimal EAx / EBx Fine Volume Slides — done
91. Minimal 6xy Vibrato + Volume Slide — done
92. XM Effect Memory Foundation — done
93. Minimal E1x Fine Portamento Up — done
94. 1xx / 2xx Portamento Effect Memory Expansion — done
95. XM Effect Coverage Refresh After Portamento Memory — done
96. Bounded XM diagnostics playable-order count alignment — testing/tooling follow-up
97. Minimal 0xy Arpeggio Foundation — done
98. Reference comparison stabilization against MikMod/OpenMPT
99. Focused Dxx/Bxx/E6x traversal foundation — done
100. Residual effect classification / E0x deferral cleanup — recommended next effect PR

---

# Phase 1 — Core Tracker

Goal: fully functional pattern editor.

Tasks:

- static cursor row behavior
- stable pattern viewport
- cursor field navigation
- edit mode
- row gutter alignment
- channel header alignment
- horizontal scrolling

Status: In progress

Checkpoint: Tracker Editor Static Row Milestone
- static highlight row implemented
- wrap behavior implemented
- shared viewport slot mapping implemented
- unified layout fix applied for gutter/body alignment

Current note:
- read-only tracker display, stable viewport behavior, keyboard navigation, and pattern selection are implemented
- full editing remains future work

---

# Phase 2 — Pattern Editing

Add full editing capabilities.

Features:

- note entry
- instrument entry
- effect entry
- copy/paste rows
- pattern insertion/deletion
- pattern length editing

---

# Phase 3 — Audio Engine and Playback Accuracy

Improve first-pass playback into deterministic, reference-comparable playback.

Components:

- PlaybackEngine
- SoftwareMixer
- Playback trace diagnostics
- Audio comparison tooling

Features:

- default CoreAudio-hosted runtime C mixer playback, with
  `VTX_AUDIO_BACKEND=c_mixer` and `VTX_AUDIO_BACKEND=c_mixer_coreaudio` as
  explicit CoreAudio aliases
- retired `VTX_AUDIO_BACKEND=av_audio` value that falls back to the CoreAudio C
  mixer with a diagnostic fallback reason
- local-only runtime C mixer output diagnostics through `VTX_C_MIXER_RUNTIME_TRACE_PATH`, including channel-scoped stop/replacement evidence, true global clear/stop evidence, applied/deferred gain/pan/sample-step update evidence, render callback counters, callback frame ranges, planned/applied event frame deltas, deterministic same-frame burst/order diagnostics, sustained carried-voice association diagnostics, post-gain output level summaries, clipping recommendations, row-transition snapshots, and runtime gain/headroom policy breadcrumbs
- local-only runtime C mixer sample-time position diagnostics that compare the C
  mixer frame cursor against `PlaybackEngine` order/pattern/row/tick without
  changing tracker viewport behavior
- CoreAudio DefaultOutput Audio Unit runtime output host as the default C mixer
  host, with the retired SourceNode path no longer selectable
- local-only output-host summaries that distinguish capture duration, debug
  stop duration, planned song end, and continued output after planned
  event-stream exhaustion
- runtime C mixer song-end/tail handling for the default CoreAudio host, with
  capture duration remaining capture-only
- CoreAudio runtime C mixer render-core slimdown that keeps the normal callback
  path to render, output-buffer copy, fixed counters, and fixed-capacity
  diagnostics, with no SourceNode host reintroduction
- CoreAudio host hardening/corpus evidence that summarizes backend/host,
  callback duration/budget, realtime safety, route/sample-rate, capture, and
  song-end/tail health
- transport, timing, pitch, loop, panning, volume-column, and envelope compatibility passes
- stop-position preservation plus a tracker-style plain Spacebar play/stop
  shortcut for manual playback debugging
- playback debug seek and trace export
- local reference comparison workflow against MikMod/OpenMPT for already-rendered WAVs
- deterministic software mixer skeleton for future offline rendering
- bounded offline render harness for deterministic mixer validation
- synthetic one-shot sample rendering through the offline mixer harness
- synthetic forward and ping-pong loop rendering through the offline mixer harness
- synthetic volume and panning envelope foundations through the C-backed offline mixer path
- synthetic absolute-frame voice scheduling through the C-backed offline mixer path
- synthetic tracker row/tick timing through the C-backed offline mixer path
- minimal synthetic pattern playback through the C-backed offline mixer path
- minimal bounded `PlaybackSong` to synthetic adapter renders through the C-backed offline mixer path
- parsed `PlaybackInstrument.volumeEnvelope` point mapping for bounded offline adapted renders, using the timing active at the event row
- explicit XM linear-frequency period/frequency sample-step mapping for bounded offline adapted renders, with Amiga pitch behavior still deferred
- simple deterministic linear interpolation for fractional C-backed offline sample steps, without full OpenMPT/MikMod resampler parity
- conservative volume-column set-volume, set-panning, and row-level volume/panning slide mapping for bounded offline adapted renders, without full volume-column parity
- minimal bounded/offline volume/panning state updates for empty-note
  volume-column set-volume/set-panning cells, regular effect-column `Cxx` set
  volume, regular effect-column `8xx` set panning, and nonzero tick-level
  `Axy` volume slides after tick 0
- minimal row-level `Hxy` global volume slides for bounded offline adapted
  renders, with clamped adapter global-volume state, active voice updates,
  future trigger gain mapping, and diagnostics for no-op/clamped/both-nibble
  cases
- minimal `Fxx` speed/BPM timing changes for bounded offline adapted renders, without full effect parity
- minimal `9xx` sample offset starts for same-cell bounded offline adapted
  note/sample triggers, with per-channel `900` memory replay and deterministic
  missing-memory diagnostics
- minimal `0xy` arpeggio support for bounded offline and CoreAudio C mixer
  runtime adapter paths, with deterministic base/x/y sample-step updates,
  same-cell note folding, no-active-voice diagnostics, `000` no-op behavior,
  and no broad arpeggio memory
- minimal `1xx`/`2xx` portamento up/down and minimal `3xx` tone portamento
  support for bounded offline adapted renders, with no-retrigger 3xx target
  setting, per-channel `100`/`200` memory replay, generic C mixer sample-step
  updates, diagnostics, and `5xy` plus volume-column tone portamento still
  deferred
- minimal `E2x` fine portamento down support through one row-level
  linear-period/sample-step adjustment in the runtime/offline C mixer adapter
  path, with same-cell note folding, no-active-voice diagnostics, `E20` effect
  memory deferred, and no broad E-command memory
- minimal `E1x` fine portamento up support through one row-level
  linear-period/sample-step adjustment in the runtime/offline C mixer adapter
  path, with same-cell note folding, no-active-voice diagnostics, `E10` effect
  memory deferred, and no broad E-command memory
- minimal `4xy` vibrato support through deterministic linear-period
  sample-step updates in the runtime/offline C mixer adapter path, with `400`
  and single-zero nibbles replaying available per-channel vibrato memory and
  supported `E4x` waveform/control state while missing memory,
  volume-column vibrato, and unrelated effect memory remain deferred
- minimal `E4x` vibrato-control support that stores per-channel sine/default,
  ramp-down, square, and deterministic-random waveform state for later `4xy`
  and `6xy` rows without emitting direct audio events; unsupported control
  values remain explicit deferred diagnostics
- minimal `6xy` vibrato + volume slide support through prior channel vibrato
  memory plus the existing row-level volume-slide/gain path, with
  `600` replaying available vibrato memory and missing vibrato memory,
  volume-column vibrato, and unrelated effect memory still deferred
- minimal `EAx`/`EBx` fine volume slide support through one row-level clamped
  channel-volume adjustment in the runtime/offline C mixer adapter gain path,
  with same-cell note folding, no-active-voice diagnostics, `EA0`/`EB0` effect
  memory deferred, and no broad E-command memory
- minimal `E9x` retrigger support for bounded offline adapted renders, with
  `E90` effect memory and retrigger volume-change variants still deferred
- minimal `ECx` note cut and `EDx` note delay support for bounded offline
  adapted renders, with broader effect parity still deferred
- first-pass parsed volume-envelope sustain, envelope loop, note value `97`
  key-off release, and post-key-off fadeout behavior for bounded offline adapted
  renders, without full FT2/OpenMPT envelope parity or panning envelopes
- deterministic PCM16 WAV export for bounded offline adapted `PlaybackSong` candidate renders, local-only
- developer-only bounded XM candidate WAV helper using the existing metadata loader, playback builder, and offline export path
- explicit developer-only render duration/frame controls for longer local bounded candidate WAVs, preserving the default safety clamp
- optional local bounded adapter diagnostics JSON export from the candidate WAV helper
- local-only bounded candidate/reference WAV smoke wrapper that delegates to `scripts/audio-compare.py`
- local-only mismatch-window correlation report that maps comparison JSON to approximate adapter rows/events and summarizes applied, ignored/no-op, deferred/unsupported, and unknown command frequency in the worst windows
- local-only bounded findings report template for private local candidate/reference comparison evidence
- fixed 256-voice scheduled/active C mixer storage for bounded offline renders,
  with diagnostics for configured capacities, accepted scheduled voices, reject
  counts, and rejected event coordinates
- explicit `--window-rows` row-windowed scheduling for long developer-only
  candidate WAV exports, with aggregate/per-window capacity diagnostics and
  practical carryover of active sample position, forward/ping-pong loop state,
  volume-envelope position, key-off/release, fadeout, gain, pan, and active
  `1xx`/`2xx`/`3xx`/`4xy`/`6xy` sample-step state across fresh C mixer windows
  where the bounded adapter can determine it
- deterministic offline active-voice gain/pan update events so supported
  bounded adapter state changes can affect carried voices after their note
  trigger without changing runtime playback
- fixed 32-frame gain/pan update micro-ramping for changed active-voice
  bounded/offline C mixer update events, with interrupted ramps restarting from
  the current interpolated value and `ECx` note cuts remaining immediate
- export-time output gain/headroom controls and clipping diagnostics for
  developer-only bounded PCM16 candidate WAVs, applied after Float32 rendering
  and before PCM16 conversion without changing C mixer DSP semantics
- local/offline click/discontinuity diagnostics for candidate WAV
  adjacent-sample jumps and optional correlation with bounded adapter events,
  with the analyzer itself remaining diagnostics-only
- minimal bounded/offline `E9x` retrigger, `ECx` note-cut, and `EDx`
  note-delay diagnostics, including applied, no-active/no-note, E90 no-op, and
  out-of-row cases
- pattern traversal/timing diagnostics for bounded offline renders, reporting
  applied/safe-diagnostic `Bxx`, `Dxx`, and `E6x` traversal plus deferred
  `EEx`, contextual `Fxx`, and other observed `E` subcommands
- local-only XM effect coverage summaries for bounded offline diagnostics JSON
  and runtime C mixer traces, with detected/applied/deferred/unsupported/no-op
  command counts, first source coordinates, unresolved key-off/no-active
  buckets, and a conservative next-effect recommendation
- ADR 005 documents that the current Swift software mixer remains the deterministic reference/specification harness while the eventual hot-path mixer moves toward a small C-compatible core behind a Swift wrapper
- ADR 007 documents the feature-flagged runtime C mixer backend plan; the
  current default has advanced to the CoreAudio C mixer, with the old AVAudio
  backend retired

---

# Phase 4 — Visualization

Scopes system.

Features:

- waveform scopes
- animated activity bars
- rave-style visualizer

---

# Phase 5 — Instrument System

Panels:

Instrument Editor  
Sample Editor  

Features:

- sample trimming
- loop editing
- envelope editing

---

# Phase 6 — Module Management

Panels:

Module Info  
Preferences

Features:

- module metadata
- playback settings
- UI configuration

---

# Phase 7 — Advanced Editing

Features:

- pattern automation
- effect preview
- keyboard recording

---

# Phase 8 — Release

Prepare VoodooTracker X open source release.

Tasks:

- polish UI
- optimize performance
- documentation
- packaging

---

# Future Project

VoodooTracker Pro

Commercial version with additional capabilities:

- AI sample generation
- AI instrument creation
- AI pattern generation
- AI-assisted composition

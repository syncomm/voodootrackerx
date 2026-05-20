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

Default runtime playback still uses the `AVAudioPlayerNode` /
`AVAudioUnitVarispeed` backend. An experimental runtime C mixer skeleton now
exists behind the developer-only `VTX_AUDIO_BACKEND=c_mixer` flag, but it is
opt-in only and does not replace the AVAudio backend. The software mixer path is
groundwork for offline rendering and future reference comparison; it can render
synthetic one-shot sample voices plus
synthetic forward and ping-pong loops, volume/panning envelope foundations,
absolute-frame, row/tick scheduled, minimal synthetic pattern voices, and tiny
bounded `PlaybackSong` adapter segments through the offline harness with
source-to-synthetic diagnostics. Those bounded candidate renders can now be
written as deterministic PCM16 WAV files for local comparison. Parsed
`PlaybackInstrument.volumeEnvelope` points can be converted into the C-backed
frame-based envelope representation for those bounded offline adapted renders
only, with first-pass sustain, envelope loop, note value `97` key-off release,
and post-key-off fadeout semantics now represented in that offline path. Adapted
note triggers carry explicit XM linear-frequency period/frequency
sample-step mapping where `PlaybackSong.usesLinearFrequencyTable` is true, and
the adapter applies volume-column set-volume/set-panning plus a conservative
row-level subset of volume-column volume and panning slides to event gain/pan.
It also applies minimal bounded/offline state updates for empty-note
volume-column set-volume/set-panning cells, regular effect-column `Cxx` set
volume, regular effect-column `8xx` set panning, and nonzero row-level `Axy`
volume slides; where a carried voice is active, deterministic gain/pan update
events can update that voice after its original note trigger, and changed
active-voice gain/pan updates are smoothed by a fixed 32-frame C mixer
micro-ramp in the bounded/offline path. Minimal row-level `Hxy` global volume
slide is also applied in the bounded/offline adapter: the adapter carries a
clamped `0...64` global-volume value, defaults to `64`, applies up/down Hxy
slides once at the source row, updates active voices through the same generic
gain-update path, and uses that multiplier for later note triggers. `H00` is
diagnosed as a no-op without effect memory, and both-nibble Hxy parameters use a
diagnosed up-nibble-precedence policy. The bounded adapter also applies
minimal `Fxx` timing changes for offline renders only: `F01...F1F` updates
speed, `F20...FFF` as byte parameters updates BPM, and `F00` is diagnosed as an
ignored no-op. It also applies minimal nonzero `9xx` sample offsets to same-cell
note/sample triggers in bounded offline renders only, diagnoses `900` as
ignored/deferred/no-op, and skips out-of-range offsets safely. Minimal `ECx`
note cut and `EDx` note delay are supported in bounded offline renders only;
`ECx` hard-cuts the active adapted voice at the requested tick and `EDx` delays
only normal same-cell note triggers. Minimal `1xx`/`2xx` portamento up/down and
minimal `3xx` tone portamento are supported in bounded offline renders only:
`1xx`/`2xx` slide the tracked active voice's linear-period/sample-step on later
row ticks, and a normal-note `3xx` sets a linear-frequency target for the active
voice without retriggering the sample before later ticks schedule deterministic
C mixer sample-step updates toward the target. No-active, zero-parameter,
no-target, no-speed, clamped, and non-linear pitch-table cases are diagnosed as
applicable, while `5xy` and volume-column tone portamento remain deferred.
Minimal `E9x` retrigger is also supported
in bounded offline renders only; it schedules same-channel retrigger starts at
the row's effective tick frames, preserves the tracked active voice's sample,
offset, pitch, volume, pan, loop, and envelope mapping, and diagnoses `E90`,
no-active-voice, and out-of-row cases without effect memory. Fractional
C-backed offline sample steps now use simple
deterministic linear interpolation, including safe no-loop ends, forward-loop
wraps, and ping-pong turnarounds. Bounded offline note triggers now use parsed
XM instrument sample maps/keymaps when a valid multi-sample mapping is present,
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
It now also reports applied `1xx`/`2xx` portamento-slide diagnostics, applied
`3xx` tone-portamento diagnostics, and deferred pitch-modulation counts and
source coordinates for arpeggio, remaining portamento-family commands, vibrato,
tremolo, and volume-column vibrato/tone-portamento commands, with a conservative
pitch-effect next-PR recommendation when one bucket dominates local evidence.
Bounded diagnostics also count
pattern traversal and timing hazards such as `Bxx` position jump, `Dxx` pattern
break, `EEx` pattern delay, contextual `Fxx`, and other observed `E`
subcommands without implementing traversal behavior; filled reports and
generated audio artifacts stay outside git. The developer-only helper keeps its default
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
key-off/release, fadeout, gain, pan, and active `1xx`/`2xx`/`3xx`
sample-step state. Unsupported/deferred effects and full tracker voice semantics
remain separate targeted work. Developer-only bounded
candidate WAV exports now also report Float32 output headroom/clipping
diagnostics and can apply explicit `--gain` or `--headroom-db` before PCM16
conversion without changing runtime playback, C mixer DSP semantics, or the
default output gain. Local/offline click/discontinuity diagnostics can now
analyze candidate WAV adjacent-sample jumps and optionally correlate top jumps
with bounded adapter diagnostics such as gain/pan updates, retriggers, note
cuts/delays, note triggers, looped/carryover/window events, and
key-off/fadeout evidence.
The bounded/offline C mixer now reports gain/pan ramp settings and counts in
diagnostics. ADR 007's feature-flagged runtime C mixer plan now has an initial
implementation skeleton: it remains developer opt-in, keeps the AVAudio backend
as the default fallback, uses an AVAudioEngine-hosted pull source, and keeps
tracker viewport, parser, and broad UI work out of the backend PR. Runtime C
mixer A/B listening diagnostics now add a local-only JSONL trace for backend
selection, PlaybackEngine order/row/tick context, note/key/stop events, C mixer
add/clear/stop calls, render-frame counters, and channel-scoped stop/replacement
evidence. The experimental runtime C mixer now tags runtime voices by caller-owned
channel id so immediate channel stops use `c_mixer_stop_channel` instead of
clearing all C mixer voices. Same-channel runtime note replacement now uses a
deterministic 32-frame replacement stop ramp, emits
`c_mixer_stop_channel_ramped`, and lets the new replacement voice start while
the old tagged voice fades out briefly. True transport stop/reset still clears the
runtime C mixer globally. Runtime C mixer output diagnostics now extend that
local-only trace with render callback counters, requested/rendered frame counts,
zero-fill/underrun evidence where detected, output peak/RMS and
clipping/overrange summaries, row-transition snapshots, backend lifecycle breadcrumbs,
and explicit runtime headroom policy reporting. The experimental runtime C
mixer now applies a conservative runtime-only output gain/headroom policy at the
AVAudio source-node handoff, defaults to `-10 dB`, reports post-gain clipping
diagnostics and recommendations, and accepts local-only gain/headroom
environment overrides only when `VTX_AUDIO_BACKEND=c_mixer` is selected.
Offline export `--auto-headroom` remains separate, and AVAudio remains the
default runtime backend. The experimental runtime C mixer now bridges supported
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
This keeps the runtime C mixer experimental and opt-in while reducing trace
noise around the remaining update deferrals.
Runtime C mixer stabilization diagnostics now add a local trace summary helper
for post-ramping A/B passes. It reports output health counters, stop/replacement
paths, immediate hard stops, clear-all evidence, active/loaded voice ranges,
applied/suppressed/stored/deferred update categories, and event bursts from
runtime JSONL traces. Recent local listening still found hard cuts/stumbles in
the opt-in runtime C mixer while default AVAudio playback and offline C-backed
WAV renders were cleaner, which points the next investigation toward runtime
event/state scheduling parity and the richer offline adapter event stream
rather than C mixer core DSP, runtime headroom, parser changes, or tracker UI.

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
38. Minimal bounded traversal behavior for `Bxx`/`Dxx`/`EEx` — separate later PR
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
61. Reference comparison stabilization against MikMod/OpenMPT

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
- PlaybackAudioEngine
- SoftwareMixer
- Playback trace diagnostics
- Audio comparison tooling

Features:

- first-pass XM playback through `AVAudioPlayerNode` / `AVAudioUnitVarispeed`
- experimental opt-in runtime C mixer skeleton through `VTX_AUDIO_BACKEND=c_mixer`, with AVAudio still the default backend
- local-only runtime C mixer A/B and output diagnostics through `VTX_C_MIXER_RUNTIME_TRACE_PATH`, including channel-scoped stop/replacement evidence, true global clear/stop evidence, applied/deferred gain/pan/sample-step update evidence, render callback counters, post-gain output level summaries, clipping recommendations, row-transition snapshots, and runtime gain/headroom policy breadcrumbs
- transport, timing, pitch, loop, panning, volume-column, and envelope compatibility passes
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
  volume, regular effect-column `8xx` set panning, and nonzero row-level `Axy`
  volume slides
- minimal row-level `Hxy` global volume slides for bounded offline adapted
  renders, with clamped adapter global-volume state, active voice updates,
  future trigger gain mapping, and diagnostics for no-op/clamped/both-nibble
  cases
- minimal `Fxx` speed/BPM timing changes for bounded offline adapted renders, without full effect parity
- minimal nonzero `9xx` sample offset starts for same-cell bounded offline
  adapted note/sample triggers, with `900` and effect memory still deferred
- minimal `1xx`/`2xx` portamento up/down and minimal `3xx` tone portamento
  support for bounded offline adapted renders, with no-retrigger 3xx target
  setting, generic C mixer sample-step updates, diagnostics, and `5xy` plus
  volume-column tone portamento still deferred
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
  `1xx`/`2xx`/`3xx` sample-step state across fresh C mixer windows where the bounded
  adapter can determine it
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
- pattern traversal/timing hazard diagnostics for bounded offline renders,
  reporting `Bxx`, `Dxx`, `EEx`, contextual `Fxx`, and other observed `E`
  subcommands while keeping actual traversal implementation separate
- ADR 005 documents that the current Swift software mixer remains the deterministic reference/specification harness while the eventual hot-path mixer moves toward a small C-compatible core behind a Swift wrapper
- ADR 007 documents the feature-flagged runtime C mixer backend plan, and the
  initial skeleton keeps the AVAudio backend default while making the C mixer
  runtime path opt-in only

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

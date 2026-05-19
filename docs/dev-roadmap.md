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

Runtime playback still uses the `AVAudioPlayerNode` / `AVAudioUnitVarispeed`
backend. The software mixer path is groundwork for offline rendering and future
reference comparison; it can render synthetic one-shot sample voices plus
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
the adapter applies only volume-column set-volume,
set-panning, and a conservative row-level subset of volume-column volume and
panning slides to event gain/pan. The bounded adapter also applies minimal
`Fxx` timing changes for offline renders only: `F01...F1F` updates speed,
`F20...FFF` as byte parameters updates BPM, and `F00` is diagnosed as an
ignored no-op. It also applies minimal nonzero `9xx` sample offsets to
same-cell note/sample triggers in bounded offline renders only, diagnoses `900`
as ignored/deferred/no-op, and skips out-of-range offsets safely. Fractional
C-backed offline sample steps now use simple
deterministic linear interpolation, including safe no-loop ends, forward-loop
wraps, and ping-pong turnarounds. Bounded offline note triggers now use parsed
XM instrument sample maps/keymaps when a valid multi-sample mapping is present,
with diagnostics for sample-map selection, first-playable fallback,
fallback-after-invalid-map, skipped-no-valid-sample, and missing/deferred
keymap state. Amiga-table pitch behavior, full
OpenMPT/MikMod resampler parity, pitch-changing effects, full XM volume-column
parity, and full effect parity remain deferred. The path does not yet render
full XM song playback or drive live playback. Local/private XM bounded comparison findings
now have a safe report template and local-only workflow guidance, and a
developer-only `vtx_render_bounded_xm` helper can render bounded candidate WAVs
from local XM files through the existing offline export path. The helper can
optionally export local bounded adapter diagnostics JSON, and a local
correlation script can map audio comparison mismatch windows to approximate
bounded adapter rows/events and summarize applied, ignored/no-op,
deferred/unsupported, and unknown effect-column and volume-column command
frequency for focused follow-up diagnosis. Bounded diagnostics also count
pattern traversal and timing hazards such as `Bxx` position jump, `Dxx` pattern
break, `EEx` pattern delay, contextual `Fxx`, and other observed `E`
subcommands without implementing traversal behavior; filled reports and
generated audio artifacts stay outside git. The developer-only helper keeps its default
60-second safety clamp, and explicit longer local candidate WAV renders now use
documented `--seconds` / `--max-frames` controls gated by
`--allow-long-render`. Bounded adapter event-coverage diagnostics now compare
parsed normal note cells against scheduled C-backed events, report skipped-note
reasons and coordinates, expose sample-selection methods and fallbacks, and
report C mixer scheduled/active capacity values, reject counts, and rejected
event coordinates without changing runtime playback.

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
39. Chunked/windowed offline render scheduling for long candidate WAV exports — separate later PR
40. Feature-flagged runtime backend switch
41. Reference comparison stabilization against MikMod/OpenMPT

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
- minimal `Fxx` speed/BPM timing changes for bounded offline adapted renders, without full effect parity
- minimal nonzero `9xx` sample offset starts for same-cell bounded offline
  adapted note/sample triggers, with `900` and effect memory still deferred
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
- pattern traversal/timing hazard diagnostics for bounded offline renders,
  reporting `Bxx`, `Dxx`, `EEx`, contextual `Fxx`, and other observed `E`
  subcommands while keeping actual traversal implementation separate
- ADR 005 documents that the current Swift software mixer remains the deterministic reference/specification harness while the eventual hot-path mixer moves toward a small C-compatible core behind a Swift wrapper

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

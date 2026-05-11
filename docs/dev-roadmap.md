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
backend. The software mixer skeleton is groundwork for offline rendering and
future reference comparison; it does not yet play samples or drive live
playback.

Immediate audio accuracy sequence:

1. Software Mixer Skeleton Behind AudioEngine — done
2. Offline Render Harness for Software Mixer — next
3. One-shot sample rendering
4. Forward and ping-pong loop rendering
5. Volume, panning, and envelope rendering
6. Timing and effect integration
7. Feature-flagged runtime backend switch
8. Reference comparison stabilization against MikMod/OpenMPT

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
- local reference comparison workflow against MikMod/OpenMPT
- deterministic software mixer skeleton for future offline rendering
- offline render harness and mixer sample rendering still pending

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

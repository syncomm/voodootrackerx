# VoodooTracker X — Development Roadmap

This document is the lightweight, phase-based roadmap.

Primary roadmap:
- Use `docs/roadmap.md` for the detailed PR-by-PR plan and current sequencing.

Use this file when you want a short phase summary rather than the full implementation roadmap.

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

# Phase 3 — Audio Engine

Implement playback.

Components:

PatternPlayer  
ChannelState  
SampleMixer  
AudioEngine

Features:

- pattern playback
- tempo control
- channel muting

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

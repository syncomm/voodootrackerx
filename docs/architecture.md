# VoodooTracker X — Architecture

This document describes the major architectural components of VoodooTracker X.

---

# Application Structure

Language: Swift  
UI Framework: AppKit  
Target Platform: macOS

Major systems:

- Module Parser
- Pattern Editor
- Audio Engine
- Instrument System
- Visualization System

---

# High-Level Architecture

Application

AppDelegate  
TrackerWindowController  

Core UI Components:

PatternGridView  
PatternViewportMetrics  
PatternCursor  
PatternRenderer  

---

# Module Layer

Handles reading tracker formats.

Current supported format:

XM (FastTracker II modules)

Planned:

MOD  
IT  
S3M

Key components:

Module  
Pattern  
Row  
ChannelEvent

## Current Parsing Strategy

Module loading currently uses a hybrid parsing approach.

- `core/ModuleCore` in C handles core parsing responsibilities such as module headers, metadata extraction, and lower-level parsing support.
- The Swift app layer still performs additional parsing and full-loading work where the current workflow needs richer in-memory data for the UI.
- Some overlap between the C and Swift parsing paths is currently intentional, or at least tolerated, so the app can keep moving without blocking on a full parser consolidation.

Agents should treat this as an active architecture boundary, not cleanup debt that can be removed opportunistically.

Rules for current work:

- Correct behavior comes first.
- Do not remove the Swift parser just because similar responsibilities exist in `ModuleCore`.
- Do not force parser unification during unrelated cleanup or UI work.
- Any attempt to make one parser path the sole source of truth should be treated as a separate, explicit architecture decision.

## Future Parser Direction

The long-term source-of-truth direction is still open.

Open design question:

- `ModuleCore` may eventually become the full source of truth for module loading.
- The Swift layer may remain responsible for some higher-level loading or UI-facing transformation responsibilities.

This should be resolved deliberately in a future design pass, with behavior preservation and migration risk reviewed explicitly.

---

# Pattern Model

Structure:

Module
  Pattern[]
    Row[]
      ChannelEvent[]

ChannelEvent fields:

note  
instrument  
volume  
effectType  
effectParam

---

# View Model

PatternViewportMetrics
- maps pattern rows to viewport coordinates

PatternCursor
- active row
- active channel
- active field

---

# Rendering Layer

PatternGridView

Responsibilities:

- draw rows
- draw channel columns
- draw cursor highlight
- draw beat markers

Rendering approach:

- custom NSView drawing
- minimal subviews

## Tracker Editor Architecture Principles

- Use a single viewport model for tracker row visibility and navigation state.
- Build one canonical visible slot list for the viewport.
- Share rendered geometry between gutter, pattern body, and highlight behavior when possible.
- Avoid split layout pipelines that independently compute row positioning for gutter and body.

---

# Audio Engine (Future)

Planned architecture:

AudioEngine  
PatternPlayer  
ChannelMixer  
SampleVoice

Possible backend:

AVAudioEngine

---

# Visualization

Scopes system.

Displays waveform activity per channel.

Phase 1:
synthetic data

Phase 2:
audio engine integration

Legacy reference:

legacy/voodootracker-classic/app/scope-group.c

---

# Editing System

Modes:

Navigation  
Edit  
Play  
Record

Future live note entry will feed events into Pattern data model.

---

# UI Layout

Planned layout regions:

Top
- logo
- pattern controls

Center
- pattern editor

Bottom
- status / transport

Left
- optional tools panel

---

# Design Philosophy

Priorities:

1. Fast composition workflow
2. Keyboard navigation
3. Visual rhythm clarity
4. Minimal UI latency

Classic tracker workflow is preferred over modern DAW paradigms.

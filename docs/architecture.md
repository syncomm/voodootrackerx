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

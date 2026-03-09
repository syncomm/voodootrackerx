# VoodooTracker X — Project Checkpoint

## Project
VoodooTracker X is a modern resurrection of the classic 1990s Linux tracker **VoodooTracker**, originally written by Gregory Hayes and featured in the book *Linux Music and Sound*.

The goal is to create a **modern macOS tracker** inspired by:

- VoodooTracker
- FastTracker II
- Renoise
- classic demoscene trackers

The project is open source and written primarily in **Swift + AppKit** with a C-based legacy reference.

Repository:
https://github.com/syncomm/voodootrackerx

---

# Current Architecture

### UI
AppKit based

Main components:

AppDelegate  
TrackerWindowController  
PatternGridView  
PatternViewportMetrics  
PatternCursor  

Pattern grid currently renders:

- rows
- channels
- note / instrument / volume / effect columns
- beat highlight rows
- static cursor row (in progress)

---

# Current Features Implemented

### Module parsing
Working XM parser.

Supports:

- pattern count
- row count
- channel count
- pattern order table
- note events
- instrument
- volume column
- effect type
- effect parameter

CLI utility:

swift run mc_dump --json file.xm

---

### Pattern Editor (Track Editor)

Working features:

- pattern rendering
- multiple channels
- row numbering
- beat highlighting (every 4 rows)
- horizontal scrolling
- channel headers
- cursor highlighting (red box)
- field navigation
- edit mode toggle
- clearing cells
- hex entry for instrument/effect fields

Currently fixing:

- static play cursor row behavior

---

# Static Tracker Cursor Behavior

Target behavior (classic tracker style):

The highlight row **does not move**.

Instead:

- pattern text scrolls behind the row
- the row acts as a visual timing reference

Position:

- fixed around **mid-screen vertically**

Initial load:

(empty space)  
(empty space)  
row 00  <-- static bar  
row 01  
row 02  

Navigation example:

Down arrow:

(empty)  
row 00  
row 01  <-- static bar  
row 02  
row 03  

Wraparound:

Last row → row 00

No fake rows should appear.

---

# Known Regression

Current branch:

feature/track-editor-static-row

Problems introduced by last change:

- highlight row not anchored correctly
- viewport math incorrect
- extra fake rows rendered at bottom
- red cursor sometimes clipped
- cursor navigation broken

Fix in progress.

---

# Visual Design

Inspired by:

- VoodooTracker
- FastTracker II
- Renoise

Current UI:

- dark theme
- yellow beat rows
- channel headers
- ASCII logo banner

Future improvements planned:

- pinned row number gutter
- vertical channel divider rendering
- improved grid layout
- better column alignment

---

# Upcoming Core Features

### Track editor completion
- static viewport anchor row
- stable cursor rendering
- wraparound navigation
- record mode

### Live note entry
Play notes using keyboard while pattern playing.

Modes:

Navigation  
Play  
Edit  
Record  

---

# Audio Engine (future milestone)

Planned components:

AudioEngine  
SampleMixer  
PatternPlayer  
ChannelState  

Audio output likely via:

AVAudioEngine  
or  
CoreAudio

---

# Scopes (visualizers)

Classic tracker scopes will be implemented.

Phase 1:
- scope UI
- synthetic waveform data

Phase 2:
- feed from audio engine

Possible design:

- multicolor rave-style bars
- translucent overlay behind VoodooTracker logo

Legacy reference:

legacy/voodootracker-classic/app/scope-group.c

---

# Future Panels

Tabs similar to classic tracker:

Tracker  
Instrument Editor  
Sample Editor  
Module Info  
Preferences  

---

# VoodooTracker Pro (future commercial version)

Additional AI-powered features:

- AI sample generator
- AI instrument creator
- AI pattern generation
- AI track composition assistance

---

# Development Workflow

AI-assisted development using:

codex-cli

Typical workflow:

codex --ask-for-approval on-request

Branches:

feature branches for each subsystem.

Important current branch:

feature/track-editor-static-row

---

# Current Development Priority

Finish the **Track Editor** before implementing:

- sound engine
- scopes
- instrument editor
- sample editor

The track editor is the **core experience** of a tracker.

---

# Author

Gregory Hayes

- Original VoodooTracker author
- Arctic Code Vault contributor
- Open source developer

---

# Project Vision

Create the **best modern tracker inspired by the demoscene era** while keeping the speed, clarity, and workflow of classic trackers.

Focus on:

- composition speed
- visual rhythm clarity
- keyboard-driven workflow
- creative exploration


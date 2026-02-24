# Legacy VoodooTracker Preservation Map

This document maps key behaviors from the legacy Linux/GTK VoodooTracker codebase (`legacy/voodootracker-classic`) that VoodooTracker X should preserve in spirit and behavior.

Scope for the modern project:
- Use the legacy code to understand behavior and workflow expectations.
- Do not copy legacy code verbatim.
- Reimplement cleanly for modern macOS/AppKit architecture.

## Preserve First: Tracker Feel (Behavior)

These are the highest-value parts to preserve in VoodooTracker X.

### 1) Keyboard-first tracker workflow
Preserve the fast, keyboard-centric editing loop:
- Row navigation (`Up`, `Down`, `Page Up`, `Page Down`)
- Cursor movement across note/instrument/volume/effect columns
- Channel navigation (`Tab` / reverse tab behavior)
- Note entry from keyboard layout mapping
- Immediate row advance after note entry

Legacy references:
- `legacy/voodootracker-classic/app/track-editor.c:117` (`tracker_page_handle_keys`)
- `legacy/voodootracker-classic/app/track-editor.c:321` (`insert_note`)
- `legacy/voodootracker-classic/app/tracker.c:77` (`tracker_set_patpos`)
- `legacy/voodootracker-classic/app/tracker.c:97` (`tracker_note_typed_advance`)
- `legacy/voodootracker-classic/app/tracker.c:184` (`tracker_step_cursor_item`)
- `legacy/voodootracker-classic/app/tracker.c:198` (`tracker_step_cursor_channel`)
- `legacy/voodootracker-classic/app/notekeys.c:89` (`init_notekeys`)
- `legacy/voodootracker-classic/app/notekeys.c:127` (`key2note`)

### 2) Pattern editing concepts (not exact UI implementation)
Preserve the editing concepts and shortcuts model:
- Pattern position scrolling and viewport sync
- Pattern/track cut/copy/paste workflows
- Track/channel-oriented editing mental model
- Pattern position jump shortcuts (quarter/half/etc.)

Legacy references:
- `legacy/voodootracker-classic/app/track-editor.c:147` (pattern/track ops via `F3..F5` variants)
- `legacy/voodootracker-classic/app/track-editor.c:44` (editor-local buffers for pattern/track/block)
- `legacy/voodootracker-classic/app/tracker.c` (tracker widget rendering, cursor, x-panning)
- `legacy/voodootracker-classic/app/tracker.h` (tracker widget state / cursor model)

### 3) Pattern grid representation and display semantics
Preserve the visible pattern-grid semantics:
- Row numbers
- Per-channel note cells (note/instrument/volume/effect/fxparam)
- Cursor focus by sub-field (item within channel)
- Multi-channel horizontal panning when channel count exceeds visible width

Legacy references:
- `legacy/voodootracker-classic/app/tracker.c:211` (`note2string` formatting of note cells)
- `legacy/voodootracker-classic/app/tracker.c:250` (row/channel rendering loop)
- `legacy/voodootracker-classic/app/tracker.h` (`cursor_ch`, `cursor_item`, `leftchan`, display fields)

## File Formats to Preserve (First Pass)

First-pass compatibility target for VoodooTracker X remains:
- `MOD` (read-only compatibility first)
- `XM` (read-only compatibility first)

Legacy references:
- `legacy/voodootracker-classic/app/xm.h` (`XM`, `XMPattern`, `XMNote`, instruments/samples structs)
- `legacy/voodootracker-classic/app/xm.c:609` (`XM_Load` entry point)
- `legacy/voodootracker-classic/app/xm.c:626` (XM signature check: `Extended Module: `)
- `legacy/voodootracker-classic/app/xm.c:630` (fallback to MOD loader)
- `legacy/voodootracker-classic/app/xm.c:525` (`xm_load_mod`)
- `legacy/voodootracker-classic/app/xm.c:550` (MOD signature handling e.g. `M.K.`)
- `legacy/voodootracker-classic/app/xm.c:134` (`xm_load_xm_pattern`)

Notes for modern implementation:
- Match observed parsing behavior and compatibility edge cases where practical.
- Keep modern parser code isolated from UI.
- Add compatibility tests using small fixtures and later real-world regression modules (redistribution-safe).

## Audio Subsystem (Reference Only)

The legacy app includes an audio thread, mixer/driver abstraction, and playback command pipe protocol. This is useful as a behavior and architecture reference only.

What to learn from it:
- Separation between UI thread and audio thread
- Command/response pipe protocol for playback control
- Driver abstraction boundaries (open/prepare/sync/stop)
- Playback state transitions and transport commands

Legacy references:
- `legacy/voodootracker-classic/app/audio.h:24` (control pipe commands)
- `legacy/voodootracker-classic/app/audio.c:431` (`audio_init`)
- `legacy/voodootracker-classic/app/audio.c:131` (`audio_ctlpipe_play_song`)
- `legacy/voodootracker-classic/app/audio.c:159` (`audio_ctlpipe_play_pattern`)
- `legacy/voodootracker-classic/app/audio.c:187` (`audio_ctlpipe_play_note`)
- `legacy/voodootracker-classic/app/audio.c:214` (`audio_ctlpipe_stop_playing`)
- `legacy/voodootracker-classic/app/audio.c:358` (command dispatch loop handling pipe messages)
- `legacy/voodootracker-classic/app/xm-player.c` (legacy playback engine/effect processing; reference behavior only)

Backend references:
- OSS backend present in this imported snapshot:
  - `legacy/voodootracker-classic/app/drivers/oss.c:60` (`driver_oss`)
  - `legacy/voodootracker-classic/app/drivers/oss.c:124` (`oss_open`)
  - `legacy/voodootracker-classic/app/drivers/oss.c:250` (`oss_prepare`)
  - `legacy/voodootracker-classic/app/drivers/oss.c:279` (`oss_sync`)
  - `legacy/voodootracker-classic/app/drivers/oss.c:330` (`oss_stop`)
- ALSA note:
  - No ALSA backend source is present in this imported snapshot under `app/drivers/`.
  - If/when ALSA code is imported from another historic branch/snapshot, treat it the same way: reference for behavior and architecture only.

## UI / App Flow Reference Points

These files help understand how the original app wired the tracker/editor/audio together:
- `legacy/voodootracker-classic/app/main.c` (startup, audio init, driver/mixer selection, GTK main loop)
- `legacy/voodootracker-classic/app/gui.c` (main UI, key dispatch, transport wiring, editor integration)
- `legacy/voodootracker-classic/app/track-editor.c` (tracker page interactions and editing commands)
- `legacy/voodootracker-classic/app/tracker.c` (custom tracker widget rendering/navigation)

Useful anchors:
- `legacy/voodootracker-classic/app/gui.c:173` (`gui_mixer_play_song`)
- `legacy/voodootracker-classic/app/gui.c:183` (`gui_mixer_play_pattern`)
- `legacy/voodootracker-classic/app/gui.c:216` (`gui_mixer_play_note`)
- `legacy/voodootracker-classic/app/gui.c:389` (main key dispatch path into handlers)
- `legacy/voodootracker-classic/app/gui.c:407` (`handle_standard_keys`)

## Important Constraint: No Verbatim Copying

Do not copy legacy source code verbatim into VoodooTracker X.

Use the legacy repo to:
- Match workflow behavior
- Match parsing expectations / compatibility behavior
- Validate UX details (navigation, editing, pattern semantics)
- Understand sequencing between UI, transport, and playback

Implement new code in modern style for:
- AppKit UI
- macOS audio stack (not OSS/ALSA)
- Testable parser/core modules
- Clear module boundaries and documentation

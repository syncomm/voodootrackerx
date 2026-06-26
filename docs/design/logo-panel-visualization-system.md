# Logo-Panel Visualization System

## 1. Purpose

This document records the future VoodooTracker X logo-panel visualization
direction. It is design-only: it does not change `LogoPanelView`, playback,
runtime audio, the C mixer, parser architecture, tracker viewport behavior,
editor/note-audition behavior, the control panel, or release workflow.

The goal is to keep the visual product direction explicit while deferring
implementation until runtime metrics, gain/headroom policy, editing, and safe
UI state boundaries are stronger.

## 2. Product Direction

VTX should keep FastTracker, demoscene, and rave nostalgia, but it should not
be limited to a 1990s scope clone. The product target is a modern Mac-native
tracker first, with possible iPad, VoodooTracker Pro, and AI-assisted workflow
extensions later.

The winning direction is VTX architecture plus FT2 continuity and ramping
discipline. VTX can aim higher than legacy trackers while staying simple,
elegant, and fast for making music.

## 3. What VTX Should Learn From FT2-Clone

FT2-clone remains valuable as a playback/reference implementation and as a
source of architectural lessons. The important lessons for VTX are:

- preserve audio continuity across row, tick, loop, and replacement boundaries
- use ramping deliberately for voice replacement, note cuts, gain changes, and
  pan changes
- keep float mixing and final output clamping/headroom policy separate
- handle sample loops and interpolation with care
- synchronize visual state with playback state when a visual claims to be
  tracker-position-aware

These are behavior lessons, not a mandate to copy FT2-clone source code or its
runtime architecture.

## 4. What VTX Should Not Copy From FT2-Clone

VTX should not make FT2-style per-channel scopes the product destination by
default. Per-channel scopes are useful reference visuals, but they are not the
same as final mixed output meters, clipping diagnostics, or a modern
performance visual layer.

VTX should also preserve its own strengths:

- Swift/AppKit orchestration around a Mac-native application shell
- deterministic adapter planning for runtime/offline alignment
- public fixtures and public-safe diagnostics
- release engineering and file-hygiene discipline
- future shared engine potential across macOS, possible iPad, and later pro
  surfaces

Copying FT2-clone would give up too much of that direction.

## 5. Logo-Panel Visual Stage Concept

The logo panel should become a VTX-native visual stage:

- at idle, the logo remains primary and readable
- during playback, the logo can fade to a tasteful partial opacity, for
  example about 80% opacity / 20% transparent
- visualization can appear behind, inside, or over the logo panel depending on
  the selected mode
- the control panel stays focused on controls; activity visuals belong in the
  logo stage or future external visual surfaces
- early implementation should be feature-flagged and visually verified before
  it becomes default behavior

The current `LogoPanelView` is intentionally static. This document does not
change its white panel, bundled logo loading, sizing, opacity, timers, or view
hierarchy.

## 6. Visual Modes

Initial and future modes can evolve without committing to one data source too
early:

- Idle logo mode: static logo-forward presentation with no audio dependency.
- Full-song playback mode: subdued animated layer tied to transport/playback
  state once safe runtime visual data exists.
- Note-audition pulse mode: short visual pulse for preview-only note audition,
  separate from full-song playback.
- Channel-energy bars mode: tracker-inspired energy bars if a safe
  per-channel or per-voice state snapshot is later designed.
- Overlaid waveform/fire-line mode: demoscene/rave-inspired line or flame
  motion that can use output or synthetic data before depending on mixer
  internals.
- Output meter mode: final mixed output level display from safe output metrics,
  explicitly separate from tracker scopes.
- Future projection/fullscreen mode: external performance visual surface using
  the same conceptual mode model after the logo-panel version is proven.
- Future user/custom visual mode: optional long-term mode surface, after the
  data contract and safety model are stable.

## 7. Data-Source Strategy

Do not decide the visualization data source prematurely. Future PRs must
distinguish these sources:

- final mixed output metrics
- runtime mixer peak, clipping, and RMS diagnostics
- per-channel or per-voice state
- audition preview state
- tracker transport position

FT2-style scopes must not be conflated with clipping meters. A per-channel
scope describes channel/voice motion; an output meter describes final mixed
signal level; clipping diagnostics describe overload risk.

Any future visual feed should consume a safe snapshot or observer feed outside
the realtime audio callback. It must not log, allocate, perform AppKit work,
parse files, or expose raw mixer internals from the callback. Any new runtime
visual data feed must be feature-gated, documented, and manually verified.

## 8. Playback Visualization Versus Note-Audition Visualization

Full-song playback and note audition should remain separate visual concepts.

Playback visualization can later follow transport state, adapter-planned
events, runtime output metrics, or a dedicated safe mixer snapshot. It must not
weaken runtime/offline determinism or bypass the runtime C mixer adapter path.

Note-audition visualization should reflect the preview-only audition path. The
current audition sink is intentionally isolated from `PlaybackEngine`, runtime
song playback, runtime diagnostics, offline render/export, and the normal
runtime mixer instance. A note-audition pulse can therefore have a different
shape, duration, and source model than full-song playback.

## 9. Realtime/Audio Safety Constraints

Visualization must never make audio less reliable. Future implementation must:

- keep AppKit drawing and animation outside the realtime audio callback
- avoid file I/O, logging, parsing, heap-heavy work, and unbounded allocation in
  callback paths
- avoid exposing mutable mixer internals directly to the UI
- preserve the current runtime audio backend and C mixer DSP behavior unless a
  later audio PR explicitly changes them
- preserve tracker viewport/static-highlight behavior
- keep diagnostics disabled by default unless a feature-specific PR says
  otherwise

The first implementation should prefer inert or synthetic visual data before
using runtime metrics.

## 10. Future External/Fullscreen/Projection Mode

External or fullscreen visualization can be a later performance feature. It
should reuse the same mode vocabulary and safe data-source model as the logo
panel, but it should not be introduced until the embedded logo-panel version is
stable.

Projection mode is a product surface, not an audio feature. It should not add a
second playback path, change mixer timing, or alter runtime scheduling.

## 11. Future User-Created Visual Modes

User-created modes may become possible later, but they require a much stronger
contract than this design PR provides:

- a stable visual data snapshot schema
- resource and performance limits
- sandboxing or a constrained declarative format
- accessibility behavior
- failure isolation so a visual cannot break playback

Do not add plugin APIs or user scripting as part of the first logo-panel
visualizer.

## 12. Accessibility/Performance Considerations

Future visuals should support reduced-motion preferences and should avoid
strobe-like behavior. The logo must remain recognizable, especially in idle
mode and when playback animation is subtle.

Performance work should start with fixed-rate UI snapshots or display-linked
rendering outside the audio callback. The implementation should measure frame
cost, avoid layout churn, and provide a low-cost mode for older Macs or future
iPad targets.

## 13. Recommended PR Sequence

1. `diagnostics: runtime mixer peak and clipping trace`
   Add or refine opt-in runtime peak, RMS, clipping, and headroom diagnostics
   without changing playback behavior.
2. `audio: design runtime gain and headroom policy`
   Decide how runtime headroom, offline export headroom, and diagnostics relate
   before UI visuals imply a level policy.
3. `visual: logo-panel visualization data-source design`
   Specify the safe snapshot/observer feed, feature gate, privacy rules, and
   verification plan.
4. `visual: logo fade state model behind feature flag`
   Add idle/playback visual state and logo opacity policy without rendering
   audio-backed visuals.
5. `visual: first inert visualization renderer using synthetic/non-audio data`
   Prove geometry, animation, reduced-motion behavior, and screenshot
   verification with no audio dependency.
6. `visual: playback metrics-backed logo visualization`
   Feed the logo-panel renderer from safe playback metrics outside the realtime
   callback.
7. `visual: note-audition visualization mode`
   Add a distinct preview pulse using the audition boundary, preserving editor
   and runtime playback behavior.
8. `visual: external/fullscreen visualization concept`
   Design the projection/performance surface after the embedded mode is proven.

## 14. Open Questions

- Should the first audio-backed mode use final mixed output metrics, transport
  position, or a deliberately synthetic animation plus playback state?
- What logo opacity value best preserves the brand while leaving visual motion
  readable during playback?
- Should channel-energy bars wait for a per-channel/voice snapshot, or should
  the first version avoid channel semantics entirely?
- How should reduced-motion and low-power modes be exposed in the UI?
- What feature gate name and manual screenshot checklist should guard the first
  visual implementation?
- When, if ever, should fullscreen/projection mode become a separate window or
  display target?

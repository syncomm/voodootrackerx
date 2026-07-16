# ADR 011: Post-v1 AUv3 Tracker Instrument Direction

## Status

Accepted as a post-v1 product direction and as guidance for present-day
architecture discipline. This decision does not authorize AU implementation.

## Context

VoodooTracker X 1.0 remains a self-contained XM-style sample/instrument
tracker. Its current sequence prioritizes editor completeness, classic XM/MOD
compatibility, deterministic playback and export, explicit editable-document
ownership, and the public synthetic XM fixture corpus.

After 1.0, VTX could either become usable inside existing DAWs or expand the
standalone app into a general third-party plug-in host. Logic/Ableton-class
hosts already own discovery, validation, routing, automation, latency,
restoration, and mixing workflows. VTX's differentiating work is its tracker
workflow, deterministic XM playback, instruments, samples, patterns, and
demoscene-style sequencing.

The existing decisions already keep Swift orchestration outside the narrow C
mixer hot path, document edits behind `applyEdit`, loaded source paths separate
from editable copies, and editor audition separate from song transport. Those
seams should remain useful without being distorted to imitate an AU before its
requirements are approved.

## Committed Decision

The product priority after VTX 1.0 is:

```text
VTX as an AUv3 tracker instrument
before
VTX as a general Audio Unit plug-in host
```

VTX should first become an AUv3 tracker instrument that runs inside host DAWs.
This lets users combine VTX's tracker sequencing and deterministic module
playback with a host's existing effects, synthesis, routing, recording, and
mastering capabilities instead of requiring VTX to rebuild a DAW host
architecture first.

Third-party Audio Unit hosting inside standalone VTX is not rejected forever.
It is lower priority, separately scoped, and not a dependency of the tracker
instrument direction.

## Post-v1 Product Direction

The format and platform sequence is:

```text
Tracker-as-a-Plugin
  macOS AUv3 first
  iPadOS AUv3 later, after the headless engine and contained UI are proven
```

AUv3 is the only approved plug-in format in this direction. The first target
is macOS AUv3 for Logic Pro and compatible macOS hosts; Ableton Live on macOS
is an intended AUv3 validation host. iPadOS AUv3 is a later phase with a
contained, touch-appropriate interface, not a direct port of AppKit windows.

No VST3, AUv2, Windows, JUCE, CMake, or cross-platform plug-in target is
planned or authorized here. Another format requires a separate future
architecture decision supported by demonstrated product need. This direction
does not rename, delay, or expand the current v1 milestone.

The deliberately narrow first product concept is:

```text
VoodooTracker X Player AU
```

Its intended first-release boundary is:

- stereo instrument output;
- one embedded VTX/XM-derived document state;
- host transport and tempo synchronization;
- deterministic render behavior;
- host MIDI note audition/triggering;
- host project recall;
- a compact, contained plug-in UI;
- offline bounce support;
- no general third-party plug-in hosting;
- no initial multi-output or stem routing;
- no initial broad parameter automation;
- no initial live pattern recording; and
- no assumption that standalone floating editor panels can be reused
  unchanged.

A later phase may become a `VoodooTracker X Tracker AU`, with deeper pattern,
order, instrument, and sample editing inside a contained plug-in interface.
That later phase is possible, not committed release scope.

This direction is post-v1: it adds no v1 feature, date, or host/OS compatibility promise.

## Future Architectural Direction

### Native AUv3 wrapper preference

Keep the standalone macOS app native Swift/AppKit. Build the future extension with
Apple-native Audio Unit APIs, bridging its adapter to the shared C-compatible
engine and Swift-owned document/orchestration layers. The AU uses a contained
view; both products share one document model, state archive, playback-plan
contract, fixture corpus, and render core.

This ADR neither adopts a cross-platform framework nor rewrites the standalone
app for framework uniformity. Later evaluation requires concrete AUv3 evidence
and a separate licensing, build-system, accessibility, maintenance, and
migration review.

Future post-v1 design should converge toward this shape:

```text
                    serializable VTX document/model
                               |
                    deterministic playback plan
                               |
                 small C-compatible pull engine
                         /               \
       standalone runtime adapter     AUv3 render adapter
```

This is a target separation of responsibilities, not a request to replace the
current runtime path. Later design work must preserve these principles:

1. Swift owns UI, orchestration, diagnostics, document state, mutation
   commands, host adapters, scheduling adapters, and tests.
2. The hot-path mixer/DSP core remains small, deterministic, real-time-aware,
   and C-compatible behind a Swift wrapper.
3. The AU consumes audio through a host-driven pull/render callback rather
   than assuming standalone push-style ownership.
4. Standalone and AU adapters share document/model semantics, playback-plan
   semantics, supported XM behavior, deterministic fixture coverage, and state
   versioning.
5. The AU adapter does not require AppKit application-singleton ownership.
6. Host transport state and preview/audition state remain separate concepts.
7. Host project state embeds a versioned serialized VTX document snapshot
   rather than depending only on an external source path.
8. File provenance and source-path ownership remain distinct from document
   state.
9. Plug-in UI uses a contained extension view with embedded modes or tabs; it
   does not assume standalone floating windows.
10. Offline bounce, seek, loop, tempo changes, sample-rate changes, buffer-size
    changes, and project recall receive explicit deterministic coverage.
11. Initial MIDI input routes to audition/trigger behavior without silently
    mutating patterns.
12. Multi-output, automation, live pattern recording, and third-party plug-in
    hosting remain later milestones.

No implementation API or binary interface is selected here. The embedded
state format, migration rules, pull-engine contract, and AU component details
require later design decisions and compatibility tests.

### Headless engine and real-time contract

The future shared processor/render core must:

- own no AppKit, UIKit, AVAudioEngine, AVAudioPlayerNode, file-dialog, or application-singleton dependency;
- perform no file I/O, parsing, serialization, logging, or diagnostics emission on the render thread;
- use no locks, blocking waits, heap allocation, or unbounded render-callback work;
- use preallocated engine state and bounded scratch storage;
- consume immutable or generation-tagged plans prepared off-thread and published atomically or lock-free;
- render deterministically across variable block sizes, sample-rate changes, reset, suspend/resume,
  offline rendering, transport discontinuities, loops, and seeks;
- retain sample-accurate event offsets within each render block;
- separate UI/controller state from processor/render state; and
- consume prepared data without asking the UI or document layer to work.

Focused tests and diagnostics outside the render callback must enforce these
expectations. This is preparation guidance only and does not authorize a
change to the current standalone runtime path.

## Host Synchronization Modes

A tracker plug-in must choose an explicit operating mode in later design.

### Host Sync Mode

Host transport, tempo, time signature, beat position, loop, and seek are
authoritative. Tracker Speed defines row/tick density relative to host musical
time, with deterministic host-PPQ-to-order/row/tick mapping. XM timing commands
that conflict with host tempo need an explicit compatibility policy; `Fxx` and
related behavior must never be silently reinterpreted.

### Internal XM Time Mode

Host play/stop gates playback, but the module retains native XM Speed/BPM.
Continuous host-grid alignment is not promised, and the UI must disclose that
this mode is not host-grid synchronized.

### Triggered Pattern/Phrase Mode

MIDI or host actions launch configured patterns, orders, or phrases. Their
quantization, latch, gate, retrigger, release, and stop semantics are explicit,
and triggering never silently mutates tracker data.

Later evidence must determine whether Host Sync ignores XM BPM changes,
translates them into row-density changes, or rejects incompatible modules;
whether XM Speed remains authoritative while host BPM owns seconds per beat;
and how `Fxx`, jumps, breaks, delays, and pattern loops interact with host
looping. It must define the PPQ-zero anchor, tempo ramps, arbitrary seeks into
effect memory, possible deterministic checkpoints/replay, host-cycle
traversal, restart position, and song end.

## Versioned VTX Project-state Archive

Host state should contain a self-contained, versioned VTX archive, not only raw
XM bytes or an external path. Without selecting a final binary schema, it
should include:

- magic, schema version, integrity information, and defensive decode-size/count limits;
- canonical orders, patterns, instruments, samples, PCM, envelopes, keymaps, and supported metadata;
- playback mode and render-critical processor state, separated from noncritical UI recall state;
- provenance without path ownership, plus optional original XM bytes for identity export; and
- migration support for later schema versions.

Serialization, compression, save, and decode occur off the render thread.
Loading validates and prepares a complete replacement snapshot before atomic
activation at a safe render boundary; corrupt, unsupported, or oversized state
fails safely. The host project remains portable without the original XM, and
AUv3 document/preset state maps to the same archive contract. Source identity,
editable ownership, and embedded state stay distinct, while host automation
must not mirror every document field.

## MIDI Operating Modes

### Instrument Mode

Note-on/off plays the selected VTX instrument through the existing note-to-
sample keymap. Velocity, channel, pitch bend, and controller policy require
later design; MIDI events retain sample offsets inside each render block.

### Pattern/Phrase Trigger Mode

Configured notes launch patterns, orders, or phrases with explicit
quantization, latch, gate, retrigger, release, and stop behavior. Triggering
does not silently select or edit document content.

### Host-synchronized Song Mode

Host transport drives the song; MIDI remains available only for instrument
audition or explicitly configured triggering and never silently becomes
pattern entry.

Incoming MIDI never silently writes patterns. Recording into patterns is a
later feature requiring quantization and undo semantics. Automation remains
separate from document editing and tracker undo, and no render-thread document
mutation is allowed.

## Keyboard-focus Compatibility

Keyboard focus is a first-class product risk. Hosts may reserve transport and
global shortcuts, so delivery must be validated host by host and complete
tracker-key capture must not be promised in advance.

- Do not use global event taps or seize host-wide keyboard input.
- Enter explicit `VTX Keyboard Capture` by clicking/focusing the tracker, show an indicator,
  and let Escape release it when delivered.
- Text fields keep priority; unmodified tracker note/edit keys require tracker focus.
- Command, Control, and Option combinations need host-tested policy and are not swallowed indiscriminately.
- Spacebar is host-owned by default; VTX controls follow or request host transport.
- Mouse, touch, and MIDI remain alternatives where a host reserves keys.
- Focus loss, close/hide, host-window change, and deactivation clear held keys;
  key-down/up identity prevents stuck notes.
- Limitations degrade without mutation or lost state; the UI distinguishes tracker capture,
  text-entry focus, and host-owned keyboard.

The planned compatibility matrix covers Logic Pro and Ableton Live on macOS
AUv3, then Logic Pro for iPad and additional iPadOS AUv3 hosts only after the
iPad phase is approved. For each host it tests:

- lower/upper note rows; number/symbol effect keys; arrows; Delete/Backspace;
  Return/Enter; Tab/Shift-Tab; Spacebar; and Escape;
- Command-Z/Shift-Command-Z plus copy, cut, paste, and select all;
- key-down, key-up, repeat, text-field focus transitions, and focus loss while
  a note is held;
- host computer-MIDI-keyboard and transport-shortcut conflicts;
- accessibility keyboard navigation; and
- closing or hiding the editor while keys are held.

## Contained AU Interface

The first AU owns one host-provided contained view, not independent windows.
Tracker, Instrument Editor, Sample Editor, and Song/Order Editor surfaces become
embedded modes, tabs, panels, or workspaces; sheets and floating panels need
contained alternatives. Focus/first-responder lives inside that view, and render never needs UI state.

The Player AU may expose a reduced interface. A Tracker AU may deepen editing
only after focus and state recall are validated. iPadOS additionally requires
touch targets, gestures, software-keyboard behavior, and adaptive layout. This
ADR does not design the final interface.

## Present-day Preparation Guardrails

Current v1 and pre-AU work should preserve future compatibility quietly:

1. Keep document/model logic independent from AppKit views where practical.
2. Route editor mutations through explicit commands such as `applyEdit`.
3. Keep loaded-module read-only policy and editable-copy ownership explicit.
4. Keep playback plans deterministic and testable.
5. Avoid new global application singletons in reusable playback/document code.
6. Keep runtime transport state distinct from editor preview/audition state.
7. Keep UI controls separate from document mutation and audio execution.
8. Keep state serializable without assuming an owned source path.
9. Continue expanding the MIT-licensed synthetic XM corpus.
10. Preserve public fixture coverage for parser, writer, editor, audition,
    traversal, effects, and future mixer comparison.
11. Prefer adapters around stable model/engine seams over broad rewrites.
12. Do not distort current v1 architecture to simulate future AU requirements.
13. Do not change the current runtime playback path without a separately
    approved architecture or feature PR.
14. Do not broaden parser architecture as AU preparation.
15. Do not modify tracker viewport behavior as AU preparation.

## Explicitly Deferred Implementation

This decision and its documentation PR do not authorize or implement:

- an AUv3 extension target;
- source code, tests, dependencies, build settings, assets, generated artifacts, private/local data, or package/project changes;
- AUv2 work;
- VST3, Windows, JUCE, CMake, or another cross-platform plug-in target;
- a new Xcode workspace structure;
- host transport callbacks;
- host MIDI;
- host state serialization;
- AU validation;
- Logic or Ableton integration testing;
- a new pull-render runtime path;
- replacement of the current runtime backend;
- parser, mixer, scheduler, viewport, editor behavior, or Save/Save As changes;
- plug-in UI;
- automation;
- multi-output;
- third-party plug-in hosting; or
- release packaging or signing changes.

Each requires separately approved post-v1 architecture and implementation
work. Any new serialized format must also follow the repository's format-change
policy.

## Non-binding Future Workstream

The following is a planning outline, not a committed release schedule:

1. Define AUv3 product requirements and the host compatibility matrix.
2. Establish the headless-engine real-time contract and test harness.
3. Establish UI-independent document and playback package boundaries.
4. Design the internal versioned VTX project-state archive.
5. Design host timing modes, including XM timing-effect policy.
6. Prototype keyboard-focus host conformance.
7. Add a native AUv3 extension skeleton with silent or stub rendering.
8. Render deterministic stereo audio through the AU callback.
9. Validate variable buffer sizes and sample rates.
10. Validate transport, tempo, seek, loop, restart, and offline bounce.
11. Add host MIDI Instrument Mode.
12. Add project-state save, recall, and migration.
13. Add the minimal contained Player AU interface.
14. Validate Logic Pro for macOS conformance.
15. Validate Ableton Live for macOS AUv3 conformance.
16. Evaluate iPadOS AUv3 feasibility and a contained touch UI.
17. Harden performance, lifecycle, signing, validation, distribution, and release.
18. Only then approve a deeper Tracker AU editing roadmap.
19. Consider automation, pattern recording, and multi-output through separate decisions.

## Open Questions

Later evidence and design work must resolve:

- the exact AU component type and subtype;
- supported macOS/iPadOS and minimum Logic Pro/Ableton Live versions;
- whether the first AU is player-only or lightly editable;
- host-tempo versus XM-tempo ownership and exact PPQ-to-order/row/tick mapping;
- tempo ramps, arbitrary seeks, stateful-effect reconstruction, and
  host-loop/tracker-loop interaction;
- the embedded document-state format and migration policy;
- preset versus project-state responsibilities;
- MIDI channel, velocity, controller, instrument routing, and whether pattern
  launch is gate, latch, one-shot, or quantized;
- the host-automation boundary;
- multi-output and stem architecture;
- AU sandbox and file-access behavior;
- standalone/AU feature-parity expectations;
- AU validation, signing, notarization, distribution, and Intel versus
  Apple-silicon-only macOS policy;
- how a future pull engine becomes authoritative without destabilizing
  standalone playback; and
- how keyboard-capture limitations are disclosed for each host.

## Consequences

This direction focuses post-v1 product investment on the tracker experience
VTX uniquely contributes while relying on DAWs for mature hosting and mixing.
No milestone moves and no AU behavior becomes available; host integration,
state, real-time contracts, contained UI, validation, and packaging remain future work.

## Related Decisions And Designs

See ADRs 004, 005, and 010 plus the editable-document, editor-audition, and
synthetic-XM-fixture designs under `docs/design/`.

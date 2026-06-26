# Module Analysis Lifecycle

This audit documents the current module-load, playback, duration, and
headroom boundaries. It is intentionally descriptive: no runtime playback,
backend, parser, C mixer, tracker viewport, editor, or release behavior changed
as part of this audit.

## Current Load Lifecycle

```text
File Open / debug VTX_OPEN_PATH
-> AppDelegate.loadModule(from:)
-> ModuleMetadataLoader.load(fromPath:)
-> PlaybackSongBuilder.build(from:modulePath:)
-> PlaybackEngine.load(song:)
-> RuntimeCMixerAdapterEventPlan.make(song:sampleRate:)
-> control panel + tracker view refresh
```

| Step | Current behavior | Main-thread / cache notes |
| --- | --- | --- |
| File open entry | `AppDelegate.openModuleFile(_:)` shows `NSOpenPanel`; `VTX_OPEN_PATH` can call `loadModule(from:)` after launch. | `AppDelegate` is `@MainActor`, so this whole load path currently runs on the main actor. |
| Metadata parse | `ModuleMetadataLoader.load(fromPath:)` calls `mc_parse_file`, extracts type/title/version/channels/pattern/instrument counts, XM defaults, song length, restart position, and order table. | Synchronous. Result is stored as `AppDelegate.loadedMetadata`. |
| Full XM pattern decode | For XM, `ModuleMetadataLoader` reparses pattern data from file with `Data(contentsOf:)`; if that fails, it falls back to the bounded `ModuleCore` XM event summary. | Synchronous disk read and decode. This preserves the current hybrid parser boundary. |
| Playback song creation | `PlaybackSongBuilder.build` maps decoded XM patterns into `PlaybackSong`, filters orders to decoded patterns, reads instrument/sample headers, decodes sample PCM, maps note-sample maps and volume envelopes, and copies initial speed/BPM. | Synchronous disk read and sample decode. Result is stored as `PlaybackEngine.song`. |
| Runtime adapter planning | `PlaybackEngine.load(song:)` stops current playback, resets transport/channel/effect state, then calls `configureRuntimeAdapterEventPlan(for:)`. For the runtime C mixer backend, this builds a full `RuntimeCMixerAdapterEventPlan` from `PlaybackSongSyntheticAdapter.adapt`. | Synchronous on load. Cached in both `PlaybackEngine.runtimeAdapterEventPlan` and the runtime C mixer audio engine. |
| Control panel state | `syncControlPanelView()` derives `ControlPanelDisplayState.loadedModuleContent` from loaded metadata and selected instrument/sample state. | Derived on demand. TIME is currently always `--:--` for loaded modules. |
| Tracker display state | Loaded XM patterns are rendered into the tracker viewport and control panel selectors. | Uses the loaded metadata pattern model; no playback analysis cache is read by the tracker viewport. |

Current load-time cached state:

- `loadedMetadata`: parsed metadata and decoded pattern grid used by UI.
- `PlaybackEngine.song`: playback-facing song, instruments, samples, and initial timing.
- `PlaybackEngine.runtimeAdapterEventPlan`: full-song runtime event plan.
- `RuntimeCMixerAudioEngine.adapterEventPlan`: copy of the plan plus a sample-time position resolver.
- Control panel content is not separately cached; it is derived each sync.

Important consequence: current file load does more than metadata display. It
also decodes sample PCM and performs full runtime C mixer adapter planning.
Moving any of this work requires a lifecycle design, because Play currently
depends on the plan being ready.

## Current Play Lifecycle

```text
Play button / Spacebar
-> AppDelegate.currentPlaybackStartContext()
-> PlaybackEngine.play(from:)
-> reset runtime state
-> enter selected PlaybackPosition
-> consume runtime adapter plan events
-> queue adapter event schedule + prepare/start CoreAudio output
```

When Play is pressed, `AppDelegate.playPressed(_:)` passes the current selected
song position, pattern, and row to `PlaybackEngine.play(from:)`. The engine
ignores Play while already playing. If a song is loaded, it resolves the start
position from the context, falling back to the current position or song start.

Playback then resets transient runtime state: tick state, pending position
commands, channel/effect/global state, row delay counters, delayed/retrigger
requests, runtime note-trigger counters, active debug context, and runtime
adapter consumption state. The cached adapter plan itself is not rebuilt on
Play.

On the first entered row, `PlaybackEngine.enter(position:)` publishes playback
follow position, prepares row/effect state, and chooses the adapter-safe path
when `RuntimeCMixerAdapterEventConsuming.hasRuntimeAdapterEventPlan` is true.
For the current runtime default, that means it calls
`consumeRuntimeAdapterEvents(context:)` instead of triggering the older simple
runtime note path. The runtime C mixer backend then configures the precomputed
adapter event schedule against the current render-core frame offset, prepares
the CoreAudio DefaultOutput Audio Unit on demand, and starts it if necessary.

Transport position is selected from the UI context first. If the context order
and row resolve to the selected pattern, that exact order/row is used. If not,
the engine searches for the first order using the selected pattern. If neither
matches, playback starts from the song start.

Stop preserves the last published playback-follow position unless the call is a
load/reset path. It invalidates timers, stops the CoreAudio output host, drains
applied adapter diagnostics, clears active C mixer voices, flushes trace
writers, resets adapter event consumption state, and publishes stopped state.
It does not rebuild the cached `PlaybackSong` or adapter plan.

## Opt-In Load / Play Timing Diagnostics

Lifecycle timing diagnostics are available behind
`VTX_PLAYBACK_TIMING_TRACE=1`. They are disabled by default and write
human-readable lines to stderr only when enabled; no trace files are written
unless another explicitly configured diagnostic does so.

Example:

```bash
VTX_PLAYBACK_TIMING_TRACE=1 \
./build/Build/Products/Debug/VoodooTrackerX.app/Contents/MacOS/VoodooTrackerX
```

The timing trace reports millisecond durations for load phases such as
`module_metadata_loader_load`, `playback_song_builder_build`,
`playback_engine_load`, `runtime_adapter_event_plan_make`,
`runtime_adapter_event_plan_configure`, `tracker_ui_refresh`, and
`control_panel_sync`.

For Play, it reports phases such as `app_play_start_context_resolution`,
`app_delegate_play_to_playback_engine_play`,
`playback_engine_start_position_resolution`,
`playback_engine_transient_runtime_state_reset`,
`playback_engine_enter_selected_playback_position`,
`runtime_adapter_event_consumption_schedule_setup`,
`runtime_adapter_event_schedule_configure`, `coreaudio_output_prepare`,
`coreaudio_output_start`, and transport/timer setup phases.

Trace fields intentionally use counts, positions, booleans, and sanitized
values. Local paths and private titles are not emitted. These diagnostics are
measurement-only: they do not move work from load to Play, compute TIME,
change runtime gain/headroom, rebuild adapter plans on Play, or change parser,
playback, C mixer DSP, tracker viewport, editor, note audition, or control
panel behavior.

## Headroom And Gain Lifecycle

There is no app load-time or Play-time module-specific headroom scan today.

| Area | Current behavior |
| --- | --- |
| Runtime output gain | `RuntimeCMixerOutputPolicy` resolves once when the runtime audio engine is created. Default runtime headroom is fixed at `-12 dB`. Environment overrides can set runtime gain or runtime headroom for diagnostics. |
| Runtime render gain | `RuntimeCMixerRenderCore` applies the resolved output gain to rendered output and records runtime output peak/overrange/clipping diagnostics. This is not auto-headroom. |
| Adapter/event gain | `PlaybackSongSyntheticAdapter` builds event gains from sample volume, channel volume, global volume, envelopes/fadeout, and related supported effects. This is part of adapter planning, not a post-render headroom scan. |
| Export headroom | `MixerWAVExportPolicy` supports explicit `--gain`, explicit `--headroom-db`, and `--auto-headroom` for offline WAV export. `--auto-headroom` needs a rendered `MixerRenderBlock` peak first. |
| Bounded render diagnostics | `vtx_render_bounded_xm` can report pre-export peak/RMS/overrange, post-gain peak/RMS, and PCM16 clipping. This is developer/offline tooling only. |

Current invalidation is coarse:

- Loading another module or File New calls `PlaybackEngine.load(song:)`, which
  clears playback state and replaces the cached song and adapter plan.
- Stopping playback clears active audio and adapter consumption state, but
  keeps the loaded song and adapter plan.
- Runtime gain/headroom policy changes are effectively process/engine
  configuration changes, not per-module cache invalidations.
- Offline export headroom diagnostics are valid only for the rendered block,
  render request, mix profile, sample rate, duration bound, and export policy
  that produced them.

Future editing must invalidate more narrowly:

- Pattern rows/order table/effect edits must invalidate duration/traversal,
  adapter plans, playback-follow resolver state, and any headroom derived from
  rendered analysis.
- Instrument/sample PCM, loop, volume, panning, envelope, finetune, relative
  note, or note-sample-map edits must invalidate adapter plans and headroom.
- Tempo/speed/effect edits must invalidate duration, row timing, adapter plans,
  and any cached analysis using row frames.
- UI-only selection changes should not invalidate audio analysis unless they
  change audition-specific preview state.

## TIME / Duration Strategy

Do not parse duration from title strings. XM titles are free text and can
contain arbitrary numbers, dates, tracker tags, or decorative text. Treating a
title as a duration source would be incorrect and would make display behavior
depend on author naming conventions rather than module traversal.

Recommended strategy:

1. Keep TIME unavailable (`--:--`) immediately after load until a real analysis
   result exists.
2. Use bounded traversal/adapter timing as the first app-visible duration
   source, because it shares the playback-facing `PlaybackSong` and existing
   `Bxx`/`Dxx`/`E6x` traversal guards.
3. Compute duration lazily after load or from an already-built adapter-analysis
   cache, not by adding another synchronous full-song pass to file load.
4. Mark the displayed duration as bounded VTX analysis, not FT2/OpenMPT exact
   song-loop parity, until traversal support is explicitly broadened.
5. If analysis hits a guard, unsupported loop policy, invalid order, overflow,
   or timeout, keep TIME as `--:--` or show an unavailable state rather than
   blocking the app.

Exactness policy:

- For a one-pass bounded VTX traversal with supported `Fxx` speed/BPM changes
  and supported traversal commands, duration can be exact for the current VTX
  model.
- For modules with open-ended loops, unsupported traversal semantics, or
  future restart behavior, duration should be bounded or unavailable.
- Pattern delay (`EEx`) and tempo/speed changes must be included before
  claiming exact duration for modules that use them. If a command is only
  diagnostic/deferred in the relevant analysis path, the TIME display should
  not present the result as exact.

Future duration cache keys should include at least: module identity/version,
order table, pattern rows and effect fields, initial speed/BPM, traversal
policy version, sample rate if stored in frames, and any edit generation.

## Future Pattern-Loop Strategy

Pattern-loop playback must preserve the runtime C mixer adapter planning path.
A safe implementation must not:

- bypass `RuntimeCMixerAdapterEventPlan`
- switch to a separate timer-driven trigger/update path
- clear or reset active C mixer audio state mid-playback in a discontinuous way
- use structural tests alone as proof that playback sounds correct

The safe boundary is an adapter-aware transport/scheduler boundary. Future
pattern-loop playback should either plan the looped range through the same
adapter machinery or teach the runtime scheduler how to seek/loop without
discarding active voice, ramp, envelope, fadeout, sample-step, and pending event
state unexpectedly.

Manual listening verification is required for any pattern-loop audio change.
Tests can prove structure, event ordering, loop guards, and state transitions,
but audible clicks/pops are output-continuity failures and need listening or
render/capture discontinuity evidence.

## Recommended Follow-Up PR Sequence

1. `diagnostics: playback analysis timing trace`
   Add disabled-by-default timing diagnostics around metadata load,
   `PlaybackSongBuilder`, adapter planning, and optional duration analysis.

2. `app: defer heavy module analysis off file load`
   Split immediate metadata/UI readiness from expensive sample decode and
   adapter planning, preserving Play behavior by gating Play until the runtime
   plan is ready or preparing it on first Play with clear UI state.

3. `ui: loaded module TIME display from bounded analysis cache`
   Add a small duration-analysis cache and display TIME only when bounded
   analysis succeeds. Keep `--:--` for unavailable/guarded cases.

4. `tests: synthetic multi-pattern loop fixture`
   Add public synthetic fixture coverage for traversal/duration and future
   loop planning without private modules or generated audio artifacts.

5. `playback: adapter-safe pattern loop design spike`
   Prototype a scheduler/transport boundary that reuses adapter planning and
   preserves active render state. Include manual listening verification.

6. `app: headroom analysis cache design`
   Decide whether app headroom should remain fixed runtime policy, use an
   offline analysis cache, or expose diagnostics only. Do not run full-song
   auto-headroom during file load.

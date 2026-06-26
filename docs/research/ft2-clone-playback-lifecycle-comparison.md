# FT2-Clone Playback Lifecycle Comparison

## 1. Purpose

This note compares VoodooTracker X's current module load, playback, headroom, timing, loop, and visual-feedback lifecycle with behavior observed in a local FT2-clone source checkout.

The goal is to document architectural lessons from a known-good reference implementation without porting code, changing runtime behavior, or treating FT2-clone internals as a drop-in design for VTX.

## 2. Scope and non-goals

In scope:

- VTX playback lifecycle as documented in `docs/design/module-analysis-lifecycle.md`, `docs/design/parsed-xm-to-c-mixer-adapter.md`, `docs/audio-comparison.md`, and current playback, adapter, C mixer, offline render, and audio comparison tooling.
- Read-only FT2-clone source inspection focused on mixer scaling, volume ramping, loop handling, live tracker state, duration display, WAV rendering, and scopes.
- Conceptual follow-up sequencing for VTX.

Out of scope:

- No FT2-clone source code copied into VTX.
- No app, audio, backend, parser, tracker viewport, editor, note audition, control panel, or release workflow behavior changes.
- No private module names, local checkout paths, WAVs, traces, screenshots, logs, generated apps, or generated packages.
- No claim that VTX should replace its adapter-plan runtime with FT2-clone's live global-state replayer.

## 3. VTX current lifecycle summary

Observed VTX behavior:

- Module loading flows through `AppDelegate.loadModule`, `ModuleMetadataLoader.load`, `PlaybackSongBuilder.build`, `PlaybackEngine.load`, and `RuntimeCMixerAdapterEventPlan.make`.
- The requested `PlaybackSong` model currently lives in `PlaybackModel.swift`. It stores orders, patterns, instruments, samples, restart behavior, end behavior, initial timing, and frequency-table mode. It does not store full-song duration or module-specific headroom analysis.
- `PlaybackSongBuilder.swift` converts parsed XM metadata and sample data into playback structures. It does not pre-scan sample peaks, render the song, compute gain policy, or compute total duration.
- `PlaybackEngine.swift` builds and caches a runtime C mixer adapter event plan at load time. `play(from:)` resets transient playback state, enters a start position, and consumes cached adapter events; it does not rebuild the adapter plan on every Play.
- `PlaybackTiming.swift` uses tracker speed/BPM timing where tick duration is `2.5 / bpm` seconds.
- Runtime output policy in `RuntimeCMixerRenderCore.swift` resolves a fixed output gain when the runtime engine is created. The default runtime headroom is currently around `-12 dB` unless diagnostic environment overrides are used.
- Runtime rendering records peak, overrange, clipping, RMS, and adjacent-sample jump diagnostics internally, but runtime playback does not run module-specific auto-headroom analysis on load or Play.
- The C mixer supports voice gain/pan ramping and same-channel replacement ramp helpers. Abrupt stop APIs also exist, so callers must choose the de-click path deliberately.
- Offline bounded rendering and WAV export support explicit gain, explicit headroom, and `--auto-headroom`. That policy is export-time only and is not currently the app/runtime policy.
- Bounded duration traversal exists in tooling, with guards around tracker control flow. The product TIME display is intentionally not implemented from a synchronous load-time full-song pass.

## 4. FT2-clone findings

Observed source areas included `src/ft2_audio.c`, `src/ft2_replayer.c`, `src/mixer`, `src/ft2_wav_renderer.c`, `src/modloaders/ft2_load_xm.c`, `src/ft2_module_loader.c`, and `src/scopes`.

Observed findings:

- I did not find a module-specific pre-scan that renders or analyzes a song to choose runtime headroom before playback.
- Runtime scaling is based on fixed and user-controlled amplification/master-volume inputs. The mixer computes an output scale from those controls rather than deriving gain from module content.
- The mixer accumulates into floating-point left/right buffers and clamps during output conversion. User amplification can still clip if set high.
- Channel, sample, envelope, global-volume, panning, and effect state are interpreted live while playback advances.
- Volume ramping is central. Triggered voices, replacement voices, volume changes, panning changes, note cuts, and some abrupt effect changes use short or tick-length ramps to reduce discontinuities.
- Sample data is prepared for interpolation and loop wrapping during load/setup. The mixer and scopes contain loop-aware interpolation paths.
- Playback is driven by a live tracker replayer from the audio callback. It does not appear to build a full immutable event plan comparable to VTX's cached runtime adapter plan.
- Pattern loops and position changes mutate live song/channel/effect state. They do not globally reset active audio state at each loop boundary.
- The visible playback time is elapsed playback time. I did not find a full-song duration precompute used for module load display.
- Scopes are fed from per-channel replayer/voice state synchronized with playback, not from the final mixed audio buffer.

Hypotheses and uncertainty:

- FT2-clone's clean playback appears to come from state continuity, careful ramping, float internal mixing, final output clamping, and sample-loop/interpolation hygiene rather than automatic headroom analysis.
- User master/amplification changes affect output level, but I did not verify whether every UI-driven global gain change is itself de-zipped. Per-channel musical volume and pan changes are clearly routed through ramp-aware paths.
- Scope visuals are tracker-style per-channel approximations synchronized to the replayer. They should not be assumed to represent exact post-mix output peaks or clipping.

## 5. Conceptual comparison table

| Area | VTX today | FT2-clone observed | VTX lesson |
| --- | --- | --- | --- |
| Runtime gain/headroom | Fixed runtime headroom by policy, diagnostics overrides, no load-time auto-headroom | Fixed/user amplification and master volume, float accumulation, final clamp | Do not assume clean reference playback requires module-specific auto-headroom |
| Offline headroom | Bounded render can apply `--auto-headroom` after rendering | WAV render uses replayer/mixer path with user render settings | Keep export policy separate from runtime policy unless explicitly redesigned |
| Load lifecycle | Builds `PlaybackSong` and cached runtime adapter plan | Parses module, normalizes/fixes data, resets live replayer state | VTX load cache is intentional; FT2 does not validate replacing it |
| Play lifecycle | Resets transient state, enters position, consumes cached adapter events | Interprets tracker rows/ticks live from audio callback | VTX loop work must preserve adapter planning or redesign it explicitly |
| Click prevention | C mixer supports ramps; caller path determines safety | Ramping is part of normal voice and volume update behavior | Make de-click behavior hard to bypass in future transport paths |
| Pattern loops | Adapter-safe pattern-loop work is deferred | Loop/jump flags change position while preserving channel state | Loop boundaries should preserve voice/effect state unless a musical reset is explicit |
| TIME/duration | Planned as bounded/lazy cache, not synchronous load analysis | Displays elapsed time; full duration precompute not observed | Keep duration analysis bounded and guarded |
| Scopes | Future design pending | Per-channel voice/scope state, not final mix buffer | Choose output-meter vs tracker-scope data source deliberately |

## 6. Runtime gain/headroom lessons

Observed source findings:

- FT2-clone does not appear to perform module-specific runtime headroom analysis before playback.
- It exposes user amplification and master volume controls and applies a fixed output scale derived from those controls.
- It accumulates internally in float buffers and clamps/saturates at final output conversion.
- Musical gain changes happen dynamically through tracker state: channel volume, sample volume, envelopes, global volume, fades, and effects.

VTX lessons:

- FT2-clone is not evidence that VTX should auto-scan modules on load or Play.
- VTX's fixed runtime headroom is conceptually defensible, but the policy deserves explicit design because offline `--auto-headroom` can create different expectations.
- A safe next step is opt-in runtime peak/clipping telemetry, not automatic runtime gain changes.
- If VTX later adds runtime auto-headroom, it should be a policy design with cache keys, invalidation, and listening gates, not an implicit side effect of opening a module.

## 7. Click/pop prevention lessons

Observed source findings:

- FT2-clone ramps note triggers, same-channel voice replacement, note cuts, volume changes, panning changes, and some abrupt effect changes.
- It uses short quick ramps for discontinuities and longer tick-length ramps for normal musical changes.
- It prepares sample data for loop/interpolation safety during load/setup and uses loop-aware mixer paths.
- I did not find a separate generic buffer-boundary smoothing pass. The prevention strategy is mostly voice-state continuity, ramps, and loop/interpolation correctness.

VTX lessons:

- The failed pattern-loop spike that bypassed normal runtime C mixer adapter planning matches the class of risk FT2-clone avoids by keeping transport and voice updates on one continuous path.
- VTX should make adapter-safe ramping the default path for voice replacement, note cut, loop entry, and transport jumps.
- Future loop and transport PRs should prove that they preserve or deliberately update active voice, effect, envelope, fadeout, panning, sample-position, and ramp state.
- Any new ramp behavior needs synthetic discontinuity fixtures plus manual listening, because avoiding clicks is partly about rendered geometry over time, not just event correctness.

## 8. Load vs Play lifecycle lessons

Observed source findings:

- FT2-clone load/setup parses module structures, copies/clamps/sanitizes data, prepares samples for interpolation, sets initial timing/frequency mode, and resets live channel/scope/time state.
- It defers row, tick, effect, envelope, and voice evolution to playback.
- It appears to interpret tracker state live rather than building a full event plan for the song.

VTX lessons:

- FT2-clone's live interpreter does not map directly onto VTX's Swift/AppKit UI plus C-compatible mixer plus cached adapter-plan runtime.
- VTX's cached adapter plan is a useful boundary for runtime/offline parity and should not be bypassed for feature spikes.
- If a feature needs state that is only known during playback, it should either be represented in the adapter plan or handled by an adapter-aware runtime scheduler.
- Load-time analysis should stay cheap and deterministic unless a design explicitly adds an asynchronous or cached analysis phase.

## 9. TIME/duration lessons

Observed source findings:

- FT2-clone displays elapsed playback time derived from playback ticks.
- I did not find an exact full-song duration pass at module load.
- WAV rendering advances the live replayer until an end condition or configured stop point, with guard behavior around tracker control flow.
- Timing precision can be configured to match FT2-style behavior more closely.

VTX lessons:

- VTX should keep loaded-module TIME as a bounded analysis result, not a synchronous load requirement.
- Duration analysis should have traversal limits, loop/jump guards, explicit unsupported states, and cache invalidation tied to module edits and timing policy.
- An elapsed playback counter is a separate product feature from total duration and may be simpler to make reliable.
- Any TIME display should explain uncertainty through UI state, not by pretending a guarded estimate is exact.

## 10. Pattern-loop lessons

Observed source findings:

- FT2-clone implements pattern loops and position changes by mutating live row/order state while preserving active channel, voice, envelope, fadeout, and effect state.
- It does not reset the whole mixer or clear active voices at every pattern-loop boundary.
- Song-end and pattern-playback modes have distinct behavior, and WAV rendering has its own stop conditions.

VTX lessons:

- The safest VTX boundary is an adapter-aware transport/scheduler layer that can jump row/order positions while preserving active runtime state and continuing to consume planned or newly scheduled mixer events.
- Resetting active audio state at loop boundaries is likely musically wrong and click-prone unless the command semantics require it.
- A pattern-loop spike should start with a synthetic multi-pattern fixture, then prove no bypass of `RuntimeCMixerAdapterEventPlan`, no abrupt voice clears, and no discontinuous timer/update path.

## 11. Scope/visualizer lessons

Observed source findings:

- FT2-clone scopes are driven from per-channel playback/voice state synchronized through a visual queue.
- Scope rendering has its own sample-position and loop handling.
- The scopes are not simply final mixed output buffers.

VTX lessons:

- VTX should decide whether its first visualizer is an output meter, a tracker-style per-channel scope, or an audition/instrument visual.
- Output meters should use mixer output buffers or runtime render metrics.
- Tracker-style scopes need per-channel voice state exposure from the adapter/runtime path and should not be confused with clipping meters.
- Note-audition visualization may need a separate data source if it does not travel through the same playback state as song playback.

## 12. Recommended VTX follow-up PR sequence

1. `diagnostics: add playback load/play timing trace`
2. `diagnostics: add opt-in runtime mixer peak and clipping trace`
3. `audio: design runtime gain and headroom policy`
4. `ui: show loaded module TIME from bounded analysis cache`
5. `tests: add synthetic multi-pattern loop-boundary fixture`
6. `playback: spike adapter-safe pattern loop transport`
7. `visual: design scope data source`

Sequencing rationale:

- Instrument first so later playback changes can be measured.
- Separate gain/headroom policy from implementation because runtime, offline export, and user expectation are currently different surfaces.
- Add TIME from bounded analysis cache before depending on it in UI workflows.
- Add loop fixtures before transport changes.
- Decide visual data source before exposing runtime internals for scopes.

## 13. Risks and listening gates

Risks:

- Treating FT2-clone's fixed/user amplification model as proof that VTX should remove runtime headroom.
- Copying FT2-clone's live replayer architecture into VTX and losing runtime/offline adapter parity.
- Adding a pattern loop by resetting voices or bypassing adapter planning.
- Applying output clamping as a substitute for a deliberate gain policy.
- Adding scopes from whichever buffer is easiest instead of matching the intended user-visible signal.

Listening and verification gates before behavior changes:

- Synthetic fixtures for same-channel replacement, note cut, volume/pan jumps, sample-loop wrap, pattern break, position jump, and pattern loop.
- Runtime peak/clipping trace behind an opt-in flag.
- Manual listening against reference renders for representative local modules without committing private module names or paths.
- Screenshot or visual capture only for UI-facing changes, kept outside the repository unless explicitly approved.
- `./scripts/check-files.sh` and targeted audio comparison tooling for any later implementation PR.

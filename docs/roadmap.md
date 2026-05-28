# VoodooTracker X Roadmap (PR-by-PR)

VoodooTracker X exists to resurrect the feel of the 1990s demo scene tracker workflow while making it approachable for a new generation of musicians.

Long-term goals:
- Restore core tracker functionality and classic workflow speed
- Recreate the look/feel nostalgia (keyboard-first pattern editing, tracker grid, visual vibe)
- Preserve MOD/XM compatibility
- Add modern enhancements after parity (UX polish, reliability, export/workflow improvements)

## Milestone 0: Foundation / CI

### PR 0.1 — Repo hygiene + basic checks
- Scope: `.gitignore`, license, file checks, basic CI wiring
- Verification: `scripts/check-files.sh`, CI green on `macos-latest`

### PR 0.2 — Minimal AppKit app skeleton
- Scope: app project, window, unit test target, CLI `xcodebuild` commands
- Verification: `xcodebuild build`, `xcodebuild test`, CI green
Status: done (including launch-window reliability fixes and standard `File` menu window actions).

### PR 0.3 — Core parser harness scaffold
- Scope: `ModuleCore`, synthetic fixtures, parser tests, `mc_dump`
- Verification: `swift test --filter ModuleCoreTests`, `swift run mc_dump ...`, CI green
Status: done.

## Milestone 1: Core Parsing (Read-Only Compatibility First)

### PR 1.1 — MOD/XM header metadata (done baseline)
- Scope: deterministic header parsing only (title/name, version, channels, counts)
- Verification: synthetic fixture tests + `mc_dump` output snapshot checks
Status: done (includes golden JSON snapshots and deterministic `mc_dump --json` output).

### PR 1.2 — XM pattern header parsing
- Scope: parse XM pattern headers (length/count/packed sizes), no note decoding yet
- Verification: unit tests with synthetic XM variants + malformed/truncated cases

### PR 1.3 — XM note/event decoding (read-only)
- Scope: decode XM packed/unpacked pattern events into testable structures
- Verification: fixture-based golden tests for decoded rows/channels

### PR 1.4 — XM instrument/sample header parsing
- Scope: instrument headers, sample headers, envelope metadata (read-only)
- Verification: unit tests for instrument/sample counts and header fields, truncation/error cases

### PR 1.5 — MOD pattern/event parsing (read-only)
- Scope: parse MOD pattern data and note/effect fields
- Verification: golden tests for known rows/cells, malformed file tests

### PR 1.6 — Compatibility smoke corpus
- Scope: add redistribution-safe sample corpus + regression harness (MOD/XM)
- Verification: parser smoke suite in CI, checksum/golden metadata assertions

## Milestone 2: Audio Bring-Up (Reference Tones to Module Playback)

Current stabilization note:
- Default audible XM playback now uses the CoreAudio DefaultOutput Audio Unit C
  mixer backend, with `VTX_AUDIO_BACKEND=c_mixer` and
  `VTX_AUDIO_BACKEND=c_mixer_coreaudio` retained as explicit CoreAudio aliases.
  `VTX_AUDIO_BACKEND=av_audio` is a retired legacy value that falls back to the
  CoreAudio C mixer with `fallbackReason=retired_backend`.
- This is still not a full FT2/OpenMPT parity claim; current playback follows
  the project C mixer path while remaining first-pass XM-compatible in areas
  where effects remain deferred.
- Timing, pitch, panning/stereo placement, sample loops including ping-pong loops, instrument volume envelopes/fadeout, volume-column behavior, debug seeking, and playback trace export have all had compatibility passes.
- ADR 004 accepted the transition toward a deterministic pull-based software mixer, and the C-backed mixer path now exists behind the playback/audio boundary. It renders silence, synthetic one-shot sample voices, synthetic forward/ping-pong loops, deterministic linear interpolation for fractional C-backed sample steps with double-precision sample positions/steps and microfixture coverage for no-loop, forward-loop, and ping-pong endpoints, volume/panning envelope foundations, frame-scheduled synthetic voices, synthetic row/tick scheduled voices, minimal synthetic patterns, and tiny bounded `PlaybackSong` adapter segments with parsed instrument sample-map/keymap selection, parsed volume-envelope point mapping plus first-pass sustain/loop/key-off/fadeout semantics, explicit XM linear-frequency pitch/period sample-step mapping where supported, conservative adapter-level volume-column set-volume/set-panning plus row-level volume/panning slide mapping, bounded/offline active-voice gain/pan updates for empty-note and same-cell `3xx` no-retrigger volume-column set-volume/set-panning cells, `Cxx` set volume, `8xx` set panning, tick-level `Axy` volume slides after tick 0 with per-channel `A00` memory replay, minimal `0xy` arpeggio, minimal `1xx`/`2xx` portamento up/down with per-channel `100`/`200` memory replay, minimal `3xx` tone portamento, minimal `5xy` tone portamento + volume slide with shared Axy-style `500` volume-slide memory reuse, minimal `E1x`/`E2x` fine portamento, minimal `EAx`/`EBx` fine volume slides, minimal `E4x` vibrato control, minimal `4xy`/`6xy` vibrato memory replay, minimal `6xy` vibrato + volume slide, minimal `Kxx` key-off scheduling, and minimal row-level `Hxy` global volume slides with a fixed 32-frame gain/pan micro-ramp for changed active-voice updates, minimal `Fxx` speed/BPM timing changes, minimal `9xx` sample offset support with per-channel `900` memory replay, minimal `E9x` retrigger support, minimal `Rxy` multi-retrigger support, minimal `ECx` note cut and `EDx` note delay support, focused `Dxx`/`Bxx`/`E6x` traversal planning in the Swift adapter/runtime layer, a fixed 256-voice scheduled/active C mixer pool for bounded offline renders, event-coverage diagnostics for missing-note investigation, and pattern traversal/timing hazard diagnostics for `EEx`, contextual `Fxx`, and other observed `E` subcommands offline only.
- Local-only bounded candidate/reference comparison reports now have a committed blank findings template and workflow guidance for private local XM modules, plus a developer-only `vtx_render_bounded_xm` helper for producing bounded candidate WAVs and optional adapter diagnostics JSON through the existing offline export path. A local correlation script can map worst comparison windows to approximate bounded adapter rows/events, including pitch step/period/frequency, sample-selection method and fallback diagnostics, sample-offset diagnostics, minimal `0xy`/`1xx`/`2xx`/`3xx`/`5xy`/`E9x`/`Rxy`/`ECx`/`EDx` diagnostics, focused `Dxx`/`Bxx`/`E6x` traversal diagnostics, volume/panning/global-volume state updates, event-coverage totals, skipped-note reasons, C mixer scheduled/active capacity values, rejected event coordinates, and remaining traversal/timing hazards, and can summarize applied, ignored/no-op, deferred/unsupported, and unknown effect-column, volume-column, and state-update command frequency for follow-up diagnosis. Filled reports and generated artifacts remain outside git.
- Local-only XM effect coverage summaries can now aggregate bounded offline diagnostics JSON and runtime C mixer JSONL traces into detected/applied/deferred/unsupported/no-op command counts, effect-memory reused/missing counts, first source coordinates, unresolved key-off/no-active buckets, effect-family counts, and a conservative next-effect recommendation. Private/local modules and generated reports remain outside git.
- Reference-render parity triage summaries can now aggregate anonymized `scripts/audio-compare.py` JSON metrics across a small local corpus, including scalar gain-normalized evidence, missing-reference status, worst-window metrics, and a conservative next-PR recommendation. This is diagnostics-only; private/local modules, generated WAVs, JSON, and Markdown reports remain outside git.
- Stem scaling diagnostics can now sum local stem WAVs or VTX solo-channel
  renders into a synthetic full mix before using them as per-channel amplitude
  references, and bounded diagnostics JSON now reports per-sample decoded PCM
  stats. The local `xm-corpus-025` audit found that both ft2-clone
  individual-track references and VTX solo-channel renders reconstruct their
  corresponding full renders. Dominant instrument/sample `23/0` also decodes
  byte-identically to the ft2-clone exported sample, with matching loop,
  volume, finetune, and relative-note metadata and disabled envelopes. This is
  diagnostics-only and does not change gain, C mixer DSP, effects, tracker
  viewport behavior, parser architecture, or runtime backend defaults.
- The ft2-clone mixer-scaling/ramping policy audit found that the primary
  48 kHz Float32 Linear reference applies 10x amplification and master volume
  256 as a final `0.3125` output factor, and that full renders and
  individual-track exports share the same scaling path. Combined with
  ft2-clone's about-`0.707` centered panning contribution, the expected
  centered full-volume scale is about `0.220971`, matching the local
  dominant-channel VTX-to-ft2 stem scalars at unity. VTX Float32 export now
  preserves overrange values for diagnostics; the full local target reported
  peak `1.925131`, RMS `0.408609`, and `206808` overrange Float32 samples at
  unity. This is diagnostics-only and points the next work at final mix/export
  reference policy before ramp-shape experiments.
- The bounded offline render helper now has an explicit opt-in FT2 reference
  mix profile. `--mix-profile vtx` remains the default linear-pan/unity-scale
  path. `--mix-profile ft2` applies equal-power center panning and the
  ft2-clone Linear `0.3125` output scale inside the offline render block before
  WAV export gain, producing the expected centered full-volume contribution
  near `0.220971`. This is reference policy alignment only; WAV export
  gain/headroom and runtime CoreAudio device safety gain remain separate.
- Smoothing diagnostics now classify `xm-corpus-025` FT2-profile top windows
  against note starts, ordinary gain updates, pan updates, volume-column and
  gain-slide/global-volume updates, replacement ramps, and note stop/cut
  events. Current VTX note starts are immediate, ordinary gain/pan changes use
  the fixed 32-frame C mixer micro-ramp, replacement voices ramp out over
  32 frames, and note-cut/retrigger/transport stop paths remain hard stops.
  Targeted ft2-clone inspection found about-5 ms quick note
  start/replacement/stop fades and one-tick ordinary volume/pan smoothing. The
  local top-window evidence points next at one-tick gain update smoothing, with
  note-start fade-in secondary and pan smoothing not currently indicated.
- The interpolation/sample-step parity pass found that the C mixer already uses
  deterministic linear interpolation with double-precision sample positions and
  sample steps. The diagnostics-only resampler/timbre follow-up documented the
  exact always-enabled floor-index linear blend policy, added high-frequency,
  impulse, ramp, forward-loop, and ping-pong microfixtures, and found from a
  targeted local ft2-clone source check that ft2-clone supports disabled,
  linear, cubic, SINC8, and SINC16 interpolation modes; the inspected
  configuration path appears to use SINC8 as the default or fallback. Local
  `xm-corpus-025` evidence remained zero-shift and level/timbre dominated, with
  brighter ft2-clone residuals in lower-correlation worst windows and no proven
  tiny C mixer boundary bug. This follow-up does not change C mixer behavior,
  does not improve parity directly, and does not solve the mismatch. The
  reference-resampler follow-up found that local MikMod
  interpolation, high-quality mixer, and 44.1/48 kHz output variants do not
  materially explain the remaining private-corpus mismatch; fixed versus
  auto-headroom primarily affects clipping/loudness, and local alignment search
  improves windows without indicating a single global offset. The focused
  loop-endpoint correctness-hardening pass confirmed exclusive XM loop-end mapping
  (`start + length`), normalized imported forward-loop runtime positions at or
  beyond the exclusive end while preserving fractional overshoot, and keeps
  exact initial source offsets at the exclusive end from reading tail samples.
  Local anonymized loop-heavy and envelope-heavy validation renders were
  byte-identical before and after this endpoint fix. This is a correctness
  hardening fix only; it did not improve the observed local reference mismatch
  for those validation modules, so the remaining mismatch is not explained by
  this exact boundary condition. The follow-up period/sample-step investigation
  added windowed active-voice pitch summaries to the local correlation report
  and reviewed the current XM linear period pipeline, including effective note,
  relative note, finetune, fixed sample base rate, output sample rate,
  tone-portamento targets, and scheduled sample-step update timing. The
  loop-heavy envelope-disabled target still points at a pitch/phase/loop-speed
  class of mismatch, but no tiny formula or C-side stepping bug was proven. The
  envelope-heavy target remains strongly confounded by envelope/key-off/fadeout
  evidence. The focused envelope timing policy audit kept this diagnostics-only:
  the current C mixer policy maps XM envelope ticks to output-frame positions,
  evaluates the first audible sample before envelope advance, holds sustain
  before loop handling while key-on, loops inclusively while key-on only, and
  releases before rendering the key-off frame. Local evidence did not prove a
  tiny envelope-policy fix; same-channel offline voice replacement/overlap is
  the stronger next parity candidate unless a reference-backed envelope
  tick-clock experiment isolates a smaller behavior change.
- Bounded diagnostics and the local correlation report now include applied `0xy` arpeggio diagnostics, applied `1xx`/`2xx` portamento-slide diagnostics, applied `3xx` tone-portamento diagnostics, applied `5xy` tone-portamento + volume-slide diagnostics, applied `E1x`/`E2x` fine-portamento diagnostics, applied `EAx`/`EBx` fine-volume-slide diagnostics, stored `E4x` vibrato-control diagnostics, applied `4xy` vibrato diagnostics, applied `6xy` vibrato + volume slide diagnostics, `900`/`1xx`/`2xx`/`A00`/`500`/`4xy`/`6xy` effect-memory reuse metadata, deferred pitch-modulation counts, source coordinates, and a conservative pitch-effect recommendation for remaining volume-column vibrato commands, `7xy` tremolo, and volume-column tone portamento. Broader pitch-modulation effects remain separate implementation work.
- The developer-only bounded XM render helper keeps its conservative 60-second default clamp while allowing explicit longer local candidate renders through documented `--seconds` / `--max-frames` controls gated by `--allow-long-render`. It also has an opt-in `--until-song-end` mode with optional `--tail-seconds N` that computes the bounded selected order-range end from the adapter timing model, including minimal supported `Fxx` timing changes, without adding default looping or full FT2/OpenMPT song-duration parity.
- Long developer-only candidate WAV exports can opt into `--window-rows` row-windowed offline scheduling so the fixed C scheduled-voice pool is reused across deterministic render windows. Diagnostics aggregate per-window scheduled, accepted, rejected, carried, continuation, and boundary-drop counts. Windowed renders now carry practical active voice state across fresh C mixer windows where the bounded adapter can determine it, including source sample position, forward/ping-pong loop state, envelope position, key-off/release, fadeout, gain, pan, active gain/pan ramp state, active `0xy`/`1xx`/`2xx`/`3xx`/`5xy`/`E1x`/`E2x`/`4xy`/`6xy` sample-step state, and supported sample-offset memory, plus supported in-window gain/pan and sample-step updates for carried voices. Unsupported/deferred effects and full tracker voice semantics remain separate targeted work.
- Developer-only candidate WAV exports now report pre-export Float32 peak/RMS/overrange counts, post-gain peak/RMS, and PCM16 clipping/clamping counts. Optional `--gain` and `--headroom-db` apply only at the export boundary before PCM16 conversion; default output gain remains unchanged when neither option is passed.
- Local/offline click/discontinuity diagnostics can now analyze a rendered WAV for large adjacent-sample jumps and optionally correlate top jumps with bounded adapter diagnostics such as gain/pan updates, retriggers, note cuts/delays, looped voices, carried voices, and window boundaries. Gain/pan update events in the bounded/offline C mixer path now use the fixed 32-frame micro-ramp, while the analyzer remains diagnostic-only and does not change playback or render behavior.
- See `docs/decisions/002-first-pass-audio-backend.md` for the accepted backend decision and intended future path.
- See `docs/decisions/003-first-pass-playback-accuracy.md` for the current playback accuracy model and known approximations.
- See `docs/decisions/004-software-mixer-transition.md` for the current mixer transition plan.
- See `docs/decisions/005-software-mixer-core-language-boundary.md` for the architecture checkpoint that clarifies the final hot-path mixer boundary before more complex envelope, timing, and effect work.
- See `docs/decisions/007-feature-flagged-runtime-c-mixer-backend.md` for the accepted planning guidance and initial implementation note for the runtime C mixer backend experiment. The CoreAudio C mixer is now the default runtime backend; `VTX_AUDIO_BACKEND=av_audio` is retained only as a retired value that falls back to that default.
- Runtime C mixer A/B listening diagnostics now provide local-only backend selection and event traces through `VTX_C_MIXER_RUNTIME_TRACE_PATH`, including PlaybackEngine order/row/tick context, C mixer add/clear/stop calls, render-frame counters, channel-scoped stop/replacement evidence, and true global clear/stop evidence. The CoreAudio C mixer has since become the default runtime backend, with `av_audio` falling back to the CoreAudio default.
- Runtime C mixer output diagnostics now extend the same local-only trace with render callback counters, requested/rendered frame counts, detected zero-fill/underrun evidence, post-gain output peak/RMS and clipping/overrange summaries, row-transition snapshots, backend lifecycle breadcrumbs, event counters, runtime gain/headroom policy reporting, and explicit reporting that the runtime C path does not apply the offline helper's `--auto-headroom` export policy. The runtime C mixer applies conservative runtime-only output gain at the CoreAudio host handoff, defaults to `-12 dB`, reports whether the gain policy is default or an environment override, and accepts local-only gain/headroom overrides when a C mixer backend is selected.
- Runtime C mixer event/update bridging now applies supported gain/pan/sample-step control updates to the current channel-tagged C mixer voice instead of treating them as a single deferred no-op class. Applied update trace rows distinguish gain/pan, sample-step, and combined updates. The remaining update handoff cases now classify no-change refreshes, epsilon-suppressed field updates, stored gain/pan channel state, no-active voice deferrals, stale-after-stop updates, missing target data, and unsupported values separately through `updateDisposition`, `updateType`, per-field update status, and cumulative epsilon/no-change counters. This does not add new XM effects or change tracker-follow behavior.
- Runtime C mixer same-channel note replacement now uses a deterministic 32-frame replacement stop ramp in the runtime backend, traced as `c_mixer_stop_channel_ramped` with ramped voice count and overlap metadata. Immediate channel stops and true transport/global stops remain hard stops.
- Runtime C mixer stabilization diagnostics now include a local trace summary helper for post-ramping passes. The helper summarizes runtime output health counters, stop/replacement paths, hard-stop evidence, normal-playback clear-all counts, active/loaded voice ranges, update categories, event bursts, and whether runtime traces show the same high-level update/effect categories as the bounded offline adapter path. The runtime C mixer precomputes a runtime adapter event plan from the bounded/offline `PlaybackSong` adapter and consumes supported plan events when available, with trace fields for event source, plan generation, planned/consumed/skipped counts, adapter categories, row/order mapping, and fallback-to-simple-runtime reasons. Runtime sample-time event application now queues planned adapter events by intended runtime frame and applies them inside runtime host callbacks by splitting the render at in-buffer event offsets. Traces report callback ranges, planned/applied frames, in-callback offsets, same-frame burst sizes, exact-frame/callback-boundary/late counts, and max planned-vs-applied deltas. Runtime sample-time position diagnostics now resolve the C mixer frame cursor back to the planned adapter order/pattern/row/tick timeline and compare it with `PlaybackEngine` timer position. The C mixer backend publishes tracker-follow position from that sample-time resolver when available. Transient/burst diagnostics add lower adjacent-sample thresholds, bounded top jumps and peaks, same-frame burst categories with voice counts, replacement ramp cleanup counters, and epsilon-suppression correlation with a local-only diagnostic epsilon override. Runtime peak-safe headroom stabilization keeps those diagnostics visible while moving the fixed default policy to `-12 dB`, without spreading same-frame events, changing C mixer DSP, or adding runtime auto-headroom. The summary helper reports PlaybackEngine-vs-C-mixer frame/millisecond delta statistics, published-follow-vs-C-mixer deltas, first divergence, constant-offset versus accumulating-drift classification, selected order-transition samples, top transients, runtime gain policy, and likely transient correlation. Unsupported XM effects remain unsupported, and broader runtime stabilization remains future work.
- Runtime C mixer live output capture tooling now records the runtime backend's actual post-runtime-gain CoreAudio host output into a bounded in-memory buffer when a C mixer backend and `VTX_C_MIXER_RUNTIME_CAPTURE_PATH` are set, then writes a local WAV outside the audio callback on stop/reset. Runtime traces and the summary helper report capture enablement, basename-only capture path, sample rate, channels, captured frames/duration, truncation, runtime gain/headroom policy, output peak/RMS, and clipping counters. This is local diagnostics only.
- Runtime C mixer event-burst and sustained-voice transition stabilization now aligns same-frame runtime adapter event ordering with the offline C mixer frame boundary: gain/pan and sample-step updates apply before note cuts and note triggers, while same-channel replacement ramps remain internal to the note trigger path. Runtime traces and the summary helper report same-frame burst IDs, event ordinals, affected channels, category counters, active/loaded voice counts before and after, ramp-down starts/completions, new voices, sustained carried voices, order-start/row-transition flags, and carried-channel association fields for no-note update cells. Unsupported XM effects remain unsupported, tracker viewport behavior is unchanged, parser architecture is unchanged, and broader runtime stabilization remains future work.
- Runtime C mixer event-burst mitigation follow-up is kept diagnostics-only after local capture comparison showed no material runtime/offline metric improvement from forcing same-frame state into replacement ramps. Replacement trace rows expose old voice state, replacement ramp start/target state, new voice id/tag when known, and booleans for gain/pan, sample-step, key-off, and fadeout state before ramp start. Runtime traces also report output-host and hardware sample-rate/channel diagnostics for downstream output delivery investigation. This does not change offline rendering semantics, add XM effects, alter tracker viewport behavior, or change parser architecture.
- Runtime C mixer format alignment now selects the runtime C mixer sample rate from the output graph/device where practical, configures the C mixer/CoreAudio-host/capture path with that rate, and keeps planned adapter event frames plus sample-time resolver frames on the same runtime timeline. Trace rows report the selected runtime sample rate, policy (`graph_aligned`, `explicit_env`, or `fallback_44100`), source, capture rate, host/device rates, and likely conversion status. Offline render behavior is unchanged, unsupported XM effects remain unsupported, tracker viewport behavior is unchanged, and parser architecture is unchanged.
- Runtime C mixer output-device and render-callback isolation diagnostics now report hashed output-device identity, optional safe route label, hardware transport type, hardware IO/latency/safety-offset fields, host start counts, route-change event fields, callback thread id/main-thread status, event-queue producer/consumer thread ids, diagnostic callback allocation-risk evidence, and a local-only follow-publication disable flag for UI/callback isolation. The trace summary also reports clean-source/dirty-live route-device versus callback candidate conclusions for local route-matrix smokes. Offline rendering is unchanged, tracker viewport code is unchanged, and parser architecture is unchanged.
- Runtime C mixer render callback diagnostics now decouple callback-side diagnostic event summaries from Swift collection growth by using fixed-capacity buffers and counters. Runtime traces and summaries report realtime-safe diagnostics status, diagnostic ring capacity, diagnostic drop count, and try-lock failure count; allocation-prone output-copy hashing is local opt-in only. This leaves offline rendering and C mixer DSP unchanged and keeps hardware/output-device stabilization separate.
- Runtime/offline mismatch window correlation diagnostics now provide a local-only bridge from full or near-full runtime capture comparisons back to runtime trace rows and optional offline diagnostics JSON. The helper imports whole-song `scripts/audio-compare.py` worst windows, accepts explicit target windows, reports runtime/offline peak and RMS, normalized correlation, RMS difference, max absolute difference, best local alignment shift, scalar normalization evidence, same-frame bursts, sustained voice association, active/loaded voice ranges, cleanup/ramp evidence, and a conservative next-PR recommendation. This is diagnostics-only; it does not modify offline render behavior, change C mixer DSP, add XM effects, modify tracker viewport behavior, or refactor parser architecture.
- ADR 008 records the current runtime-host conclusion: clean offline C mixer renders, clean runtime handoff captures, and output-copy verification made the experimental AVAudioSourceNode delivery path suspect for remaining live-only pops/clicks, but did not prove it as root cause. The SourceNode C mixer path is retired, the CoreAudio DefaultOutput Audio Unit C mixer host is now the default runtime backend, and the AVAudioPlayerNode / AVAudioUnitVarispeed backend has been retired.
- Runtime C mixer output-host diagnostics now report backend/host selection, callback shape, sample-rate/channel fields, capture status, CoreAudio OSStatus fields, and capture/playback lifecycle clocks for the single CoreAudio host. The summary helper distinguishes capture duration from debug stop duration and planned song end, and reports whether the runtime continues with active or loaded voices after the planned adapter event stream is exhausted.
- Runtime C mixer song-end/tail handling now uses the planned runtime adapter timeline to compute planned song end, adds a default 3-second runtime tail overridable with `VTX_C_MIXER_RUNTIME_TAIL_SECONDS`, and stops or silences the CoreAudio C mixer host at song end plus tail. `VTX_C_MIXER_RUNTIME_CAPTURE_SECONDS` remains capture-only, and `VTX_DEBUG_STOP_AFTER_SECONDS` remains a playback stop.
- Runtime C mixer CoreAudio render-core slimdown keeps the normal callback path to one non-blocking render-core entry for render, output-buffer copy, realtime counters, and fixed-capacity diagnostics. SourceNode graph state is no longer emitted in current CoreAudio route diagnostics; the trace summary remains tolerant of older local trace files. Offline rendering remains unchanged.
- Runtime C mixer CoreAudio host hardening/corpus evidence now uses the trace summary helper to report backend/host selection, CoreAudio OSStatus fields, sample rate/channel fields, callback counts and frame ranges, callback duration/budget health, realtime-safety flags, lock/drop counters, zero-fill/underrun/failure counters, route/device fields, capture status, and song-end/tail lifecycle evidence. The CoreAudio C mixer can be selected through the default path, `VTX_AUDIO_BACKEND=c_mixer`, or `VTX_AUDIO_BACKEND=c_mixer_coreaudio`; `VTX_AUDIO_BACKEND=av_audio` falls back to the default with `fallbackReason=retired_backend`.
- Runtime C mixer CoreAudio callback lock-contention follow-up now classifies try-lock failures as output-delivery events instead of generic diagnostics: the callback does not block, reuses the last valid callback output when available, separately counts unavailable-state silence without reporting skipped audio, and reports callback lock attempts, try-lock failures, stale-output fallbacks, skipped diagnostics, near-budget callbacks, lifecycle changes while rendering, and AudioUnit lifecycle overlap while callbacks are active. Long-run tracker-follow and row-transition trace breadcrumbs now use callback-published sample-time frames while the host is running, avoiding main-thread render-lock snapshots without changing tracker viewport behavior. Parser architecture, tracker viewport, C mixer DSP semantics, and offline rendering remain unchanged.
- Runtime C mixer CoreAudio default selection now makes the CoreAudio DefaultOutput Audio Unit C mixer host the default runtime backend. `VTX_AUDIO_BACKEND=av_audio` is now retired and falls back to the CoreAudio C mixer, `c_mixer` and `c_mixer_coreaudio` remain CoreAudio aliases, and the retired AVAudioSourceNode C mixer path remains unavailable.
- Transport stop-position preservation and a tracker-style plain Spacebar
  play/stop shortcut are implemented for manual debugging workflow. Manual Stop
  preserves the current published order/row position, play resumes from the
  current position, and Space toggles play/stop through the tracker grid focus
  path without broad shortcut parity, menu changes, pattern editing behavior,
  parser changes, C mixer DSP changes, or tracker viewport math changes.

### PR 2.1 — Audio device/output skeleton (macOS)
- Scope: audio thread/engine scaffolding (no module playback), timing-safe callback path
- Verification: unit tests for ring-buffer/state logic + manual “engine starts/stops” check

### PR 2.2 — Tone generator (sine/square test tone)
- Scope: deterministic tone output for transport/audio sanity
- Verification: unit tests on generated sample buffers + manual audible tone check

### PR 2.3 — Sample playback primitive
- Scope: play one PCM sample buffer (start/stop, rate, mono first)
- Verification: unit tests for stepping/interpolation basics + manual playback check

### PR 2.4 — Module timing/transport (no full effects)
- Scope: row/tick progression from parsed patterns, transport state only
- Verification: deterministic timing tests (songpos/patpos/tick progression)

### PR 2.5 — Basic module playback (minimal MOD/XM subset)
- Scope: note triggering + core timing for simple modules, no full effect support yet
- Verification: integration playback smoke tests + manual playback of tiny fixtures

### PR 2.6 — Effect/envelope compatibility passes
- Scope: iterate effect support and XM envelopes toward legacy behavior
- Verification: regression tests vs expected state transitions/audio metrics, manual comparison runs

## Milestone 2.7: Deterministic Software Mixer Transition

The default runtime playback now uses the CoreAudio-hosted C mixer. Offline
render/export work remains authoritative for comparison, and future audio work
should continue in small PRs that keep runtime, parser, tracker viewport, and
offline-render responsibilities separate.

### PR 2.7.1 — Software Mixer Skeleton Behind AudioEngine
- Scope: add deterministic mixer types and silence rendering behind the existing audio/playback boundary
- Verification: focused mixer tests plus existing app/parser checks
- Status: done.

### PR 2.7.2 — Offline Render Harness for Software Mixer
- Scope: add a local/offline bounded-frame render path suitable for future PCM/WAV comparison
- Verification: deterministic render tests with synthetic data only; no copyrighted module fixtures
- Status: done.

### PR 2.7.3 — Software Mixer One-Shot Sample Rendering
- Scope: render simple one-shot sample playback with deterministic sample-position accumulators
- Verification: synthetic PCM fixtures for stepping, clamping, and deterministic output
- Status: done.

### PR 2.7.4 — Software Mixer Forward and Ping-Pong Loop Rendering
- Scope: implement forward and ping-pong loop behavior in mixer-owned sample stepping
- Verification: loop edge-case tests for loop start, length, sample offset, and turnaround frames
- Status: done.

### PR 2.7.4a — ADR: Software Mixer Core Language Boundary
- Scope: document that the Swift `SoftwareMixer` remains the deterministic reference/specification harness while the eventual hot-path mixer moves toward a small C-compatible core behind a Swift wrapper
- Verification: documentation review; no runtime behavior changes
- Status: done.

### PR 2.7.4b — C Software Mixer Core Skeleton with Swift Wrapper
- Scope: add a minimal C-compatible mixer core boundary and Swift wrapper that renders deterministic silence only
- Verification: focused C-backed wrapper tests plus existing app/parser checks
- Status: done.

### PR 2.7.4c — Port One-Shot Sample Rendering to C-Backed Mixer
- Scope: port the existing synthetic one-shot sample behavior to the C-backed mixer path while keeping Swift `SoftwareMixer` as the reference/spec harness
- Verification: compare C-backed output against the existing Swift reference expectations with synthetic PCM only
- Status: done.

### PR 2.7.4d — Port Forward and Ping-Pong Loop Rendering to C-Backed Mixer
- Scope: port the existing synthetic forward-loop and ping-pong-loop behavior to the C-backed mixer path
- Verification: compare loop edge-case output against the existing Swift reference expectations with synthetic PCM only
- Status: done.

### PR 2.7.5 — C-Backed Software Mixer Volume / Panning / Envelope Foundations
- Scope: add synthetic frame-based volume envelopes and panning envelope offsets to C-backed offline sample voices
- Verification: deterministic synthetic tests for envelope interpolation, split renders, reset, clear-voices, gain, and pan behavior
- Status: done.

### PR 2.7.6 — C-Backed Software Mixer Timing and Voice Scheduling Foundations
- Scope: introduce deterministic synthetic voice scheduling/timing into the C-backed offline mixer path
- Verification: bounded render tests for synthetic scheduling boundaries, without runtime backend switching or full XM effect integration
- Status: done.

### PR 2.7.7 — Synthetic Tracker Tick and Row Timing Model
- Scope: convert simple synthetic tracker row/tick-style events into frame-scheduled C-backed mixer events
- Verification: deterministic synthetic timing tests only; no runtime backend switching, parser integration, or full XM effects
- Status: done.

### PR 2.7.8 — Minimal Synthetic Pattern Playback Through C-Backed Mixer
- Scope: introduce a tiny synthetic pattern/order representation that schedules notes through the C-backed offline mixer
- Verification: deterministic synthetic pattern tests only; no runtime backend switching, parser integration, or full XM effects
- Status: done.

### PR 2.7.9 — Parsed XM-to-Synthetic Playback Adapter Planning
- Scope: inspect the existing parsed playback model boundary and design a small adapter from parsed XM playback data into the synthetic scheduling layer
- Verification: design/tests for the adapter boundary only; no runtime backend switching or full XM compatibility claims
- Status: done.

### PR 2.7.10 — Minimal PlaybackSong-to-Synthetic Adapter
- Scope: implement the smallest safe Swift-side adapter from `PlaybackSong` into the synthetic pattern scheduling layer using constant initial speed/BPM, bounded orders, and basic note/instrument/sample triggers
- Verification: deterministic bounded offline tests with synthetic or redistribution-safe parsed fixtures only; no runtime backend switching, full XM effects, or local copyrighted module fixtures
- Status: done.

### PR 2.7.10a — Adapter Diagnostics and Bounded Offline Render Helper
- Scope: add richer in-memory source-to-synthetic diagnostics and a bounded offline render helper for tiny adapted `PlaybackSong` segments through the C-backed mixer
- Verification: deterministic helper tests for silence, basic triggers, diagnostics, frame bounds, split/reset determinism, and loop metadata; no runtime backend switching or full XM playback
- Status: done.

### PR 2.7.10b — Parsed Volume Envelope Mapping to C-Backed Mixer
- Scope: convert parsed `PlaybackInstrument.volumeEnvelope` point data into the existing C-backed synthetic volume-envelope representation for bounded offline adapted `PlaybackSong` renders
- Verification: deterministic hand-built `PlaybackSong` tests for disabled/invalid envelopes, mapped constant/ascending/descending envelopes, initial timing conversion, split/reset determinism, diagnostics, and loop metadata regression; no runtime backend switching, full pitch parity, XM effects, or full volume-column parity
- Status: done.

### PR 2.7.10c — Minimal Pitch / Note-to-Frequency Foundation for C-Backed Adapted Offline Renders
- Scope: carry a deterministic note/sample-derived playback step through bounded offline `PlaybackSong` adapter renders and the C-backed scheduled voice path, without full FT2/OpenMPT pitch parity
- Verification: deterministic hand-built `PlaybackSong` tests for neutral/default step behavior, different note-derived steps, faster high-note progression, split/reset determinism, loop and envelope regression with non-neutral steps, diagnostics, ignored note-off/invalid notes, and linear-frequency flag reporting; no runtime backend switching, XM effects, full volume-column parity, tempo changes, or local copyrighted module fixtures
- Status: done.

### PR 2.7.10d — Local-Only Bounded Reference Render Workflow Against MikMod/OpenMPT
- Scope: improve local WAV-to-WAV comparison tooling and documentation for bounded candidate/reference render diagnostics without adding renderer dependencies to CI or changing mixer behavior
- Verification: synthetic temporary WAV tests for comparison metrics, JSON output, mismatch windows, format mismatches, clipping/silence detection, and CLI error handling; local generated WAVs/reports/traces remain out of git
- Status: done.

### PR 2.7.10e — Bounded C-Mixer WAV Export Helper
- Scope: add a small offline helper that writes bounded adapted `PlaybackSong` render blocks from the existing C-backed mixer path as deterministic PCM16 WAV files for local candidate comparison
- Verification: synthetic/hand-built `PlaybackSong` tests for WAV headers, PCM16 clamping, empty renders, deterministic repeated export, and bounded adapted export; no runtime backend switching, full traversal, reference comparison, or local copyrighted module fixtures
- Status: done.

### PR 2.7.10f — Local Reference Comparison Smoke Using Bounded Candidate WAVs
- Scope: connect bounded C-backed candidate WAV export, local reference WAV generation, and `scripts/audio-compare.py` into a safe local-only smoke workflow
- Verification: synthetic temporary WAV tests for the thin local wrapper, requested JSON/Markdown output paths, missing-input errors, `/tmp` defaults, and delegation to `scripts/audio-compare.py`; no reference renderer dependency in CI and no local copyrighted module fixtures
- Status: done.

### PR 2.7.10g — Adapter Support for Volume Columns in Bounded C-Backed Offline Renders
- Scope: apply only volume-column set-volume (`0x10...0x50`) and set-panning (`0xC0...0xCF`) to bounded offline adapted `PlaybackSong` C-backed renders, with diagnostics for supported, ignored, and deferred volume-column commands
- Verification: deterministic hand-built `PlaybackSong` tests for amplitude, stereo balance, sample-volume/envelope/pitch interaction, deferred slide/vibrato/tone-portamento ranges, split/reset determinism, and unchanged effect-column deferral; no runtime backend switching, full volume-column parity, or local copyrighted module fixtures
- Status: done.

### PR 2.7.10h — Minimal Fxx Timing Changes for Bounded Offline Adapter Renders
- Scope: apply only minimal XM `Fxx` timing changes in bounded offline adapted `PlaybackSong` C-backed renders: `F01...F1F` as speed changes, `F20...FFF` as byte-parameter BPM changes, and `F00` as an ignored/no-op diagnostic. Timing changes affect following rows in the bounded adapter plan.
- Verification: deterministic hand-built `PlaybackSong` tests for no-Fxx preservation, speed/BPM row-start changes, F00 diagnostics, unchanged non-Fxx effect deferral, volume-column/envelope/pitch regressions, split/reset determinism, row-count bounds, WAV export, and existing comparison tooling; no runtime backend switching, full effect parity, or local copyrighted module fixtures
- Status: done.

### PR 2.7.10i — Adapter Support for Additional Volume-Column Slides in Bounded Offline Renders
- Scope: apply only volume-column volume slide down/up (`0x60...0x7F`), fine volume slide down/up (`0x80...0x9F`), and panning slide left/right (`0xD0...0xEF`) as row-level bounded adapter state updates for C-backed offline adapted `PlaybackSong` renders, while keeping volume-column vibrato/tone-portamento and regular effect-column behavior deferred.
- Verification: deterministic hand-built `PlaybackSong` tests for amplitude and stereo-balance changes, clamp behavior, set-volume/set-panning combinations, Fxx/envelope/pitch regressions, split/reset determinism, WAV export, and existing comparison tooling; no runtime backend switching, full volume-column parity, full effect parity, or local copyrighted module fixtures
- Status: done.

### PR 2.7.10j — Local Bounded Comparison Findings Report
- Scope: document the safe local-only workflow for bounded private-module candidate/reference WAV comparisons, add a blank findings report template, and guide first mismatch classification without committing local artifacts or changing mixer behavior.
- Verification: documentation checks plus existing audio comparison tests; no runtime backend switching, mixer DSP changes, reference renderer CI dependency, or local copyrighted module fixtures.
- Status: done.

### PR 2.7.10k — Developer-Only Bounded XM Candidate WAV Render Helper
- Scope: add a tiny developer-only local helper that loads a local XM through the existing metadata/playback builder path and writes a bounded C-backed candidate WAV via `PlaybackSongOfflineRenderer.exportWAV(...)`.
- Verification: Swift package helper tests with redistribution-safe fixtures, local minimal XM render smoke, existing audio comparison checks, and no runtime backend switching, mixer DSP changes, parser refactor, tracker viewport changes, or local copyrighted module fixtures in tests.
- Status: done.

### PR 2.7.10l — Local Trace-to-Comparison Correlation Report
- Scope: export optional local bounded adapter diagnostics JSON from the developer helper and add a local script that correlates `scripts/audio-compare.py` worst mismatch windows with approximate rows, channels, events, pitch steps, volume-column diagnostics, Fxx timing changes, envelope status, and loop metadata.
- Verification: synthetic JSON/temp-file tests only, existing bounded render helper tests, existing audio comparison tests, and no runtime backend switching, mixer DSP changes, parser refactor, tracker viewport changes, reference renderer CI dependency, or local copyrighted module fixtures.
- Status: done.

### PR 2.7.10m — Focused Pitch / Period Accuracy Pass for Bounded Offline C-Backed Renders
- Scope: make bounded adapted `PlaybackSong` renders use explicit XM linear-frequency period/frequency/sample-step calculation when `PlaybackSong.usesLinearFrequencyTable` is true, diagnose output sample rate, effective note/finetune, linear period/frequency, neutral fallback, and Amiga deferral, and verify deterministic fractional C mixer stepping without interpolation.
- Verification: deterministic hand-built `PlaybackSong` tests for monotonic steps, octave relationship, relative note, finetune, base/output sample rate behavior, invalid-rate fallback, non-linear Amiga deferral, pitch diagnostics, Fxx/volume-column/envelope/WAV regressions, split/reset determinism, audio comparison/correlation tests, and no private/local module fixtures.
- Status: done.

### PR 2.7.10n — Interpolation / Resampling Foundation for C-Backed Offline Mixer
- Scope: render fractional C-backed offline sample positions with simple deterministic linear interpolation across one-shot ends, forward-loop wraps, and ping-pong turnarounds without runtime backend changes or full OpenMPT/MikMod resampler parity.
- Verification: deterministic synthetic C mixer and hand-built `PlaybackSong` tests for integer preservation, half/non-half fractional interpolation, no-loop end safety, forward/ping-pong loop interpolation, fractional pitch-step output, split/reset determinism, diagnostics, WAV export, and existing comparison/correlation tooling.
- Status: done.

### PR 2.7.10o — Deferred Envelope Semantics for Bounded Offline Renders
- Scope: add first-pass parsed volume-envelope sustain, envelope loop, note value `97` key-off release, and post-key-off instrument fadeout semantics to bounded offline adapted `PlaybackSong` renders.
- Verification: deterministic hand-built `PlaybackSong` and C mixer tests for disabled/no-envelope preservation, mapped-envelope preservation, sustain hold, envelope loop, invalid semantic indices, note-off release, fadeout, no-note-off keyed behavior, split/reset determinism, forward/ping-pong sample loops with envelope semantics, and existing pitch/interpolation/Fxx/volume-column/WAV/comparison regressions.
- Status: done.

### PR 2.7.10p — Minimal Sample Offset 9xx for Bounded Offline Renders
- Scope: apply only nonzero XM `9xx` sample offsets to same-cell note/sample triggers in bounded offline adapted `PlaybackSong` renders by starting the C-backed scheduled voice at `xx * 256` source sample frames. Diagnose `900` as ignored/deferred/no-op without effect memory, and skip out-of-range offsets safely.
- Verification: deterministic hand-built `PlaybackSong` and C mixer tests for baseline preservation, obvious ramp offsets, pitch-step and interpolation interaction, forward/ping-pong loop interaction, out-of-range skip diagnostics, `900` diagnostics, volume-column/envelope/key-off regressions, split/reset determinism, WAV export, comparison/correlation tooling, and no private/local module fixtures.
- Status: done.

### PR 2.7.10q — Local Effect Frequency Report from Correlated Mismatch Windows
- Scope: extend the local-only correlation report to summarize applied, ignored/no-op, deferred/unsupported, and unknown XM effect-column and volume-column usage in the worst bounded candidate/reference mismatch windows, plus overall bounded diagnostic frequency and a conservative next-PR heuristic.
- Verification: synthetic temporary JSON tests only, existing audio comparison tests, existing bounded render helper tests, and no runtime backend switching, mixer DSP changes, parser refactor, tracker viewport changes, reference renderer CI dependency, or private/local module fixtures.
- Status: done.

### PR 2.7.10r — Developer Render Duration Controls for Bounded XM Candidate WAV Helper
- Scope: document and gate explicit longer local candidate WAV renders for the developer-only `vtx_render_bounded_xm` helper with `--seconds`, `--max-frames`, and `--allow-long-render`, while preserving the default 60-second safety clamp.
- Verification: focused helper argument/render-limit tests with redistribution-safe fixtures plus existing audio comparison tooling checks; no runtime backend switching, mixer DSP changes, parser refactor, tracker viewport changes, or local copyrighted module fixtures in tests.
- Status: done.

### PR 2.7.10s — Bounded Adapter Event Coverage / Missing Note Trigger Diagnostics
- Scope: add diagnostics-only event coverage for bounded `PlaybackSong` adapter renders, comparing parsed normal note cells with scheduled C-backed events and reporting skipped-note reasons, coordinates, sample-selection fallback/keymap deferrals, and C mixer voice-capacity rejections.
- Verification: deterministic hand-built `PlaybackSong` and helper JSON tests for coverage counts, skip reasons, skipped/scheduled coordinates, sample-selection metadata, capacity diagnostics, unchanged diagnostics/progress render output, correlation report summary, and no private/local module fixtures.
- Status: done.

### PR 2.7.10t — PlaybackSong Adapter Instrument Sample Map / Keymap Support
- Scope: make bounded offline adapted `PlaybackSong` note triggers select samples from parsed XM instrument 96-note sample maps/keymaps when a valid multi-sample mapping exists, and report `sample_map`, `first_playable_fallback`, `fallback_after_invalid_map`, and `skipped_no_valid_sample` diagnostics without changing runtime playback, parser ownership, C mixer DSP, or C mixer capacity.
- Verification: deterministic hand-built `PlaybackSong` tests for single-sample preservation, multi-sample mapped notes, mapped sample pitch/volume/loop/envelope metadata, invalid and empty mapped samples, missing maps, diagnostics summaries, `9xx`, `Fxx`, volume-column regressions, split/reset determinism, WAV export, existing comparison/correlation tooling, and no private/local module fixtures.
- Status: done.

### PR 2.7.10u — C Mixer Scheduled Voice Capacity / Diagnostics Hardening
- Scope: increase the bounded offline C mixer's fixed scheduled/active voice storage to 256 and report configured scheduled capacity, active capacity, accepted/rejected scheduling counts, and rejected event coordinates while keeping runtime playback unchanged.
- Verification: deterministic hand-built `PlaybackSong` and helper JSON tests for dense renders above the former capacity, zero rejects below the new capacity, clear rejects above the new capacity, split/reset determinism, existing pitch/interpolation/Fxx/volume-column/envelope/9xx/sample-map/WAV/comparison regressions, and no private/local module fixtures.
- Status: done.

### PR 2.7.10v — Pattern Traversal / Bxx-Dxx-EEx Diagnostics for Bounded Offline Renders
- Scope: add diagnostics-only counts, coordinates, statuses, JSON summary, and correlation-report context for `Bxx` position jump, `Dxx` pattern break, `EEx` pattern delay, contextual `Fxx`, and other observed `E` subcommands in bounded offline renders.
- Verification: deterministic hand-built `PlaybackSong` tests and synthetic correlation JSON tests for counts, source coordinates, deferred/applied statuses, conservative traversal recommendations, unchanged PCM output, existing helper diagnostics, comparison tooling, and no private/local module fixtures.
- Status: done.

### PR 2.7.10w — Minimal Pattern Break / Position Jump / Pattern Delay for Bounded Offline Traversal
- Scope: separate later implementation PR for the smallest safe bounded traversal behavior indicated by diagnostics.
- Verification: focused hand-built traversal fixtures, audio-invariance checks outside affected behavior, and local-only reference comparison evidence kept out of the repository.
- Status: planned.

### PR 2.7.10x — Chunked / Windowed Offline Render Scheduling For Long Candidate WAV Exports
- Scope: schedule and render long bounded candidate exports in manageable windows so the helper can safely clear/reuse C mixer state instead of requiring the fixed scheduled-event pool to hold the whole long range up front.
- Verification: deterministic long-range fixtures or generated hand-built songs that prove scheduled-event capacity is reused across windows, active capacity diagnostics remain separate, rendered output is stable across window boundaries, and private/local modules stay manual-only.
- Status: done.

### PR 2.7.10y — Window State Carryover Refinement For Windowed Offline Candidate Renders
- Scope: carry practical active voice state across explicit `--window-rows` offline render boundaries where the bounded adapter can determine it, including sample position, forward/ping-pong loop state, envelope position, key-off/release, fadeout, gain, and pan, while keeping runtime playback unchanged and avoiding new XM effect support.
- Verification: deterministic hand-built `PlaybackSong` tests for sustained one-shots, source sample position, forward and ping-pong loops, envelope position, key-off/release/fadeout, adapter volume/pan state, Fxx timing, carryover diagnostics, boundary drops, single-window matching, repeated-run determinism, existing helper/WAV/comparison coverage, and no private/local module fixtures.
- Status: done.

### PR 2.7.10z — Minimal Volume / Panning State Effects For Bounded Offline Renders
- Scope: update bounded/offline channel volume and pan state for empty-note volume-column set-volume/set-panning cells, regular effect-column `Cxx` set volume, regular effect-column `8xx` set panning, and nonzero `Axy` volume slides, with deterministic active-voice gain/pan update events where a carried voice exists. `Axy` now applies on row ticks after tick 0; leave `Hxy` global volume slide for the later targeted PR 2.7.10af.
- Verification: deterministic hand-built `PlaybackSong` and C mixer tests for update timing, active carried voices, subsequent note triggers, windowed carryover boundaries, diagnostics JSON/correlation summaries, existing WAV export/comparison tooling, and no runtime backend switching, parser refactor, tracker viewport changes, or private/local module fixtures.
- Status: done.

### PR 2.7.10aa — Minimal Note Cut ECx / Note Delay EDx For Bounded Offline Renders
- Scope: apply only XM extended-effect `ECx` note cut and `EDx` note delay in bounded/offline `PlaybackSong`-to-C-mixer renders, with diagnostics for applied, deferred, no-active/no-note, and out-of-row cases.
- Verification: deterministic hand-built `PlaybackSong` tests for delayed triggers, hard note cuts, Fxx timing interaction, sample/pitch/volume/pan/envelope/9xx metadata preservation, looped samples, windowed carryover, diagnostics JSON/correlation summaries, existing WAV export/comparison tooling, and no runtime backend switching, parser refactor, tracker viewport changes, broad effect parity, or private/local module fixtures.
- Status: done.

### PR 2.7.10ab — Mixer Output Headroom / Clipping Diagnostics and Render Gain Policy
- Scope: report pre-export Float32 peak/RMS/overrange counts, post-gain peak/RMS, PCM16 clipping counts, and an explicit developer render gain/headroom option for bounded candidate WAV export without changing runtime playback, default output gain, or C mixer DSP semantics.
- Verification: deterministic synthetic WAV/export tests, bounded render helper tests, and local-only smoke evidence kept out of the repository.
- Status: done.

### PR 2.7.10ac — Mixer Click / Discontinuity Diagnostics For Candidate WAVs
- Scope: add a local/offline analyzer for rendered WAV adjacent-sample jumps, threshold counts, clipping recap, and optional correlation with bounded adapter diagnostics for gain/pan updates, note cuts/delays, note triggers, looped/carryover/window events, and key-off/fadeout evidence.
- Verification: synthetic temporary WAV and diagnostics JSON tests only, existing audio comparison/correlation tests, existing bounded render helper tests, and no runtime backend switching, mixer DSP changes, smoothing/ramping, default gain/headroom changes, parser refactor, tracker viewport changes, or private/local module fixtures.
- Status: done.

### PR 2.7.10ad — Gain / Pan Update Micro-Ramping For Bounded Offline Renders
- Scope: smooth already-supported bounded/offline active-voice gain and pan update events with a fixed 32-frame deterministic C mixer micro-ramp, including empty-note volume-column set-volume/set-panning, `Cxx`, `8xx`, and nonzero tick-level `Axy`, while keeping `ECx` hard cuts immediate.
- Verification: deterministic C mixer and hand-built `PlaybackSong` tests for gain, pan, combined gain+pan, interrupted ramps, inactive voices, split/reset determinism, windowed carryover, diagnostics JSON, existing bounded render helper/WAV/comparison tooling, and no runtime backend switching, default gain/headroom changes, parser refactor, tracker viewport changes, or private/local module fixtures.
- Status: done.

### PR 2.7.10ae — Minimal Retrigger E9x For Bounded Offline Renders
- Scope: apply only XM extended-effect `E9x` retrigger in bounded/offline `PlaybackSong`-to-C-mixer renders, using current row speed/BPM to schedule same-channel retrigger starts and diagnosing `E90`, no-active-voice, and out-of-row cases.
- Verification: deterministic hand-built `PlaybackSong` tests for tick/frame timing, speed/BPM interaction, initial-note rows, no-active/no-op cases, pitch/sample offset/volume/pan/loop/envelope preservation, windowed carryover, diagnostics JSON/correlation/discontinuity summaries, existing WAV export/comparison tooling, and no runtime backend switching, parser refactor, tracker viewport changes, broad effect parity, or private/local module fixtures.
- Status: done.

### PR 2.7.10af — Minimal Hxy Global Volume Slide For Bounded Offline Renders
- Scope: apply only minimal row-level `Hxy` global volume slides in bounded/offline `PlaybackSong`-to-C-mixer renders, carrying a clamped adapter global-volume value, updating active voices through generic gain updates, affecting subsequent note triggers, and diagnosing `H00`, clamping, and both-nibble policy.
- Verification: deterministic hand-built `PlaybackSong` and bounded render helper tests for down/up slides, min/max clamping, no-op and both-nibble diagnostics, active voice gain updates, subsequent triggers, windowed carryover, JSON/correlation/discontinuity summaries, existing WAV export/comparison tooling, and no runtime backend switching, parser refactor, tracker viewport changes, broad effect parity, or private/local module fixtures.
- Status: done.

### PR 2.7.10ag — Portamento / Vibrato / Arpeggio Diagnostics For Bounded Offline Renders
- Scope: add diagnostics-only counts, source coordinates, correlation-report context, and conservative next-PR heuristics for deferred pitch-modulation effects: `0xy` arpeggio, `1xx` portamento up, `2xx` portamento down, `3xx` tone portamento, `4xy` vibrato, `5xy` tone portamento plus volume slide, `6xy` vibrato plus volume slide, `7xy` tremolo, and volume-column vibrato/tone-portamento ranges.
- Verification: synthetic diagnostics JSON and hand-built `PlaybackSong` tests only, existing bounded render helper and audio comparison tests, and no runtime backend switching, C mixer DSP changes, parser refactor, tracker viewport changes, or private/local module fixtures.
- Status: done.

### PR 2.7.10ah — Minimal Tone Portamento 3xx For Bounded Offline Renders
- Scope: apply only minimal XM `3xx` tone portamento in bounded/offline `PlaybackSong`-to-C-mixer renders by retaining the active voice, setting a linear-frequency target from normal-note `3xx` cells without retriggering the sample, applying same-cell instrument/sample/default-volume state to the carried voice's gain, and scheduling deterministic sample-step updates toward the target. Diagnose no-active/no-target/no-speed and keep `1xx`, `2xx`, `5xy`, and volume-column tone portamento deferred.
- Verification: deterministic hand-built `PlaybackSong` and C mixer tests for no-retrigger target setting, speed-dependent step movement, clamping, no-target/no-active diagnostics, linear-frequency relative-note/finetune targets, Fxx timing, windowed carryover, diagnostics JSON/correlation summaries, existing bounded render helper/WAV/comparison tooling, and no runtime backend switching, parser refactor, tracker viewport changes, or private/local module fixtures.
- Status: done.

### PR 2.7.10ai — Minimal Portamento Up/Down 1xx / 2xx For Bounded Offline Renders
- Scope: apply only minimal XM `1xx` portamento up and `2xx` portamento down in bounded/offline `PlaybackSong`-to-C-mixer renders by sliding the tracked active voice's linear-period/sample-step on later row ticks. Diagnose zero-parameter effect-memory no-ops, no-active-voice, clamping, and non-linear pitch-table deferral. Keep `5xy`, vibrato, arpeggio, tremolo, and volume-column tone portamento separate.
- Verification: deterministic hand-built `PlaybackSong` and bounded render helper tests for slide direction, parameter amount, tick/frame timing, Fxx interaction, clamping, no-active/no-op diagnostics, linear-frequency sample metadata, windowed carryover, diagnostics JSON/correlation summaries, existing WAV export/comparison tooling, and no runtime backend switching, parser refactor, tracker viewport changes, or private/local module fixtures.
- Status: done.

### PR 2.7.10aj — Song-End Duration / Tail Handling for vtx_render_bounded_xm
- Scope: add an opt-in calculated bounded-range duration mode such as `--until-song-end` plus `--tail-seconds N` for a short release/fadeout tail after the last bounded row/event, while keeping `--seconds` and `--max-frames` as hard debug caps and avoiding default looping.
- Verification: deterministic helper duration tests using generated or redistribution-safe inputs only, documentation that calculated duration is based on the bounded adapter's current traversal/timing model rather than full FT2/OpenMPT song-duration parity, and no runtime backend switching or private/local module fixtures.
- Status: done.

### PR 2.7.10ak — ADR: Feature-Flagged Runtime C Mixer Backend Plan
- Scope: document the future opt-in runtime C mixer backend plan, including the recommended environment flag, AVAudio backend fallback, AVAudioEngine-hosted pull-source recommendation, real-time safety rules, validation gates, and non-goals.
- Verification: documentation checks and privacy scan only; no runtime backend switching, feature-flag implementation, Swift/C code changes, parser refactor, tracker viewport changes, tests, or generated artifacts.
- Status: done.

### PR 2.7.11 — Feature-Flagged Runtime C Mixer Backend Skeleton
- Scope: implement an opt-in runtime C mixer backend skeleton behind `VTX_AUDIO_BACKEND=c_mixer`, while keeping the `AVAudioPlayerNode` / `AVAudioUnitVarispeed` backend as the default fallback.
- Verification: app playback smoke tests, backend selection tests, fallback validation, runtime diagnostics, and no parser or tracker viewport changes.
- Status: done.

### PR 2.7.11a — Runtime C Mixer A/B Listening Diagnostics
- Scope: add local-only diagnostics for the experimental runtime C mixer backend, including backend selection, PlaybackEngine order/row/tick/channel context, note trigger/key-off/channel-stop events, C mixer add/clear/stop calls, render-frame counters, and explicit tracing for the then-known per-channel stop clears-all limitation.
- Verification: backend selection tests, runtime trace path parsing, JSONL trace tests, note trigger context tests, all-voice clear/stop trace tests, existing offline render tests, app build/test, and local-only manual smoke with generated traces kept out of git.
- Status: done.

### PR 2.7.11b — Runtime C Mixer Per-Channel Voice Stop / Replacement Semantics
- Scope: replace the current experimental runtime clears-all stop behavior with channel-scoped voice stop/replacement semantics after trace evidence confirms the failure mode.
- Verification: focused runtime C mixer tests, Play/Stop smoke, A/B listening traces, and no default backend switch.
- Status: done.

### PR 2.7.11c — Runtime C Mixer Output Diagnostics / Offline Parity Investigation
- Scope: add diagnostics-first runtime C mixer output traces for explaining live-only pops/crackle and harsh order transitions against the clean bounded offline C mixer render path. Include render callback counters, requested/rendered frame counts, zero-fill/underrun evidence where detected, peak/RMS/clipping/overrange summaries, runtime headroom policy breadcrumbs, row-transition snapshots, event counters, and backend lifecycle breadcrumbs.
- Verification: focused synthetic runtime diagnostics and trace tests, existing offline render/comparison tests, app build/test, Play/Stop smoke, local-only trace generation, and no default backend switch.
- Status: done.

### PR 2.7.11d — Runtime C Mixer Headroom / Gain Policy
- Scope: apply a conservative runtime-only output gain/headroom policy to the experimental C mixer backend at the runtime host handoff, add `VTX_C_MIXER_RUNTIME_GAIN` / `VTX_C_MIXER_RUNTIME_HEADROOM_DB` overrides, and report post-gain clipping diagnostics without changing the default AVAudio backend or offline render helper behavior.
- Verification: focused runtime policy parsing tests, backend selection tests, synthetic post-gain render/clipping diagnostics tests, existing offline render/comparison tests, app build/test, Play/Stop smoke, local-only trace generation, and no default backend switch.
- Status: done.

### PR 2.7.11e — Runtime C Mixer Event Scheduling / Offline Adapter Parity Bridge
- Scope: bridge supported runtime C mixer gain/pan/sample-step updates to the existing generic C mixer voice-state update primitives for the current channel-tagged voice, with applied/deferred diagnostics and without changing the default AVAudio backend, tracker viewport, parser architecture, offline render behavior, or XM effect coverage.
- Verification: focused synthetic runtime C mixer tests for channel targeting, gain/pan updates, sample-step updates, combined updates, missing/unsupported deferrals, trace fields, per-channel replacement/stop preservation, global stop preservation, runtime headroom policy preservation, existing offline render/comparison tests, app build/test, Play/Stop smoke, local-only traces kept out of git, and no private/local module fixtures.
- Status: done.

### PR 2.7.11f — Runtime C Mixer Remaining Update Deferral Fix
- Scope: reduce remaining experimental runtime C mixer update deferrals and noisy no-op update traces by suppressing no-change and epsilon-level updates, storing safe gain/pan channel state before a voice exists, and classifying no-active, stale-after-stop, missing-data, and unsupported update cases separately.
- Verification: focused synthetic runtime C mixer tests for epsilon suppression, partial combined updates after epsilon filtering, no-change suppression, stored gain/pan state, no-active step deferral, stale-after-stop classification, missing/unsupported visibility, applied update traces, per-channel replacement/stop preservation, runtime headroom policy preservation, existing offline render/comparison tests, app build/test, Play/Stop smoke, local-only traces kept out of git, and no private/local module fixtures.
- Status: done.

### PR 2.7.11g — Runtime C Mixer Hard Stop / Replacement Micro-Ramping
- Scope: fade runtime same-channel note replacement stops over a fixed 32-frame deterministic C mixer ramp so the old tagged voice can overlap the new replacement voice briefly, while keeping immediate channel stops, true global transport stop, the default AVAudio backend, parser architecture, tracker viewport behavior, offline render semantics, and XM effect coverage unchanged.
- Verification: focused runtime C mixer tests for ramp length, channel targeting, overlap, trace fields, global stop preservation, default backend selection, runtime headroom/update policy preservation, existing offline render/comparison tests, app build/test, Play/Stop smoke, local-only traces kept out of git, and no private/local module fixtures.
- Status: done.

### PR 2.7.11h — Runtime C Mixer Stabilization / A-B Listening Diagnostics Pass
- Scope: add diagnostics-first runtime C mixer trace summary tooling and run local-only A/B listening diagnostics after per-channel stop, update bridge, headroom, epsilon filtering, and replacement micro-ramping work. Summarize output health counters, stop/replacement paths, hard-stop evidence, clear-all behavior, active/loaded voice ranges, applied/suppressed/stored/deferred update categories, event bursts, and whether runtime traces show the same high-level update/effect categories as the bounded offline adapter event stream.
- Verification: synthetic JSONL summary tests only, existing runtime/offline render tests, local-only traces and reports under ignored paths, no private/local module fixtures, no default backend switch, no tracker viewport changes, no parser refactor, no new XM effects, and no C mixer DSP semantic changes.
- Status: done.

### PR 2.7.11i — Runtime C Mixer Offline Adapter Event Stream Bridge
- Scope: feed the experimental runtime C mixer from a precomputed `PlaybackSong` adapter event plan when available, using the existing runtime order/row/tick clock to consume supported offline-adapter note, gain/pan, sample-step, note-cut, and replacement events. Keep the AVAudio backend as default, keep the C mixer opt-in only, avoid tracker viewport/parser changes, avoid new XM effects, and leave sample-time tracker-follow alignment for a later PR.
- Verification: focused synthetic runtime adapter-plan tests, runtime trace field tests, fallback tests, Play/Stop lifecycle coverage, per-channel replacement/headroom preservation, existing offline render/comparison tests, app build/test, local-only traces kept out of git, and no private/local module fixtures.
- Status: done.

### PR 2.7.11j — Runtime C Mixer Sample-Time Event Alignment Diagnostics
- Scope: add diagnostics-first runtime C mixer sample-time alignment breadcrumbs for comparing offline-adapter planned event frames with runtime application frames, callback frame ranges, same-frame event bursts, and order/row transition bursts. Keep the AVAudio backend as default, keep the C mixer opt-in only, avoid tracker viewport/parser changes, avoid new XM effects, do not change C mixer DSP semantics, and leave the actual sample-time scheduling bridge to follow-up PR 2.7.11k.
- Verification: synthetic runtime counter and trace-field tests, synthetic trace summary tests for timing deltas and bursts, existing runtime/offline render tests, app build/test, local-only traces kept out of git, and no private/local module fixtures.
- Status: done.

### PR 2.7.11k — Runtime C Mixer Sample-Time Event Scheduling Bridge
- Scope: apply already-planned runtime C mixer adapter events at their intended runtime sample frames within the runtime host callback by maintaining a sorted frame queue and splitting callback renders at event offsets. Keep the AVAudio backend as default, keep the C mixer opt-in only, avoid tracker viewport/parser changes, avoid new XM effects, and avoid C mixer DSP semantic changes beyond event timing application.
- Verification: focused synthetic runtime C mixer tests for exact note, gain/pan, step, replacement ramp, same-frame burst, queued future event, and late-event handling; trace summary tests for planned/applied frame fields and counters; existing runtime/offline render tests; app build/test; local-only traces kept out of git; and no private/local module fixtures.
- Status: done.

### PR 2.7.11l — Runtime C Mixer Playback Follow Position Drift Investigation
- Scope: expose and summarize diagnostics that map the runtime C mixer rendered frame cursor back to the planned adapter order/pattern/row/tick timeline and compare that position with `PlaybackEngine` order/pattern/row/tick at the same trace point. Classify PlaybackEngine-vs-C-mixer position drift as accumulating, mostly constant offset, or mixed evidence. Keep this diagnostics/future-bridge only; do not change tracker viewport rendering, Stop behavior, keyboard shortcuts, runtime event timing, C mixer DSP semantics, parser architecture, offline render behavior, or the default AVAudio backend.
- Verification: focused synthetic resolver and runtime trace tests, synthetic trace summary tests for row-transition deltas, PlaybackEngine-vs-C-mixer frame/millisecond delta statistics, first divergence, constant-offset versus accumulating-drift classification, existing runtime/offline render tests, app build/test, local-only runtime traces under ignored paths, and no private/local module fixtures.
- Status: done.

### PR 2.7.11m — Runtime C Mixer Tracker Follow Uses Sample-Time Position
- Scope: make the existing `PlaybackEngine.positionDidChange` follow callback publish the runtime C mixer sample-time-derived position when the experimental backend and planned adapter timeline are available. Keep the default AVAudio backend on the existing timer position, avoid tracker viewport math changes, avoid static-highlight changes, and keep the C mixer opt-in only.
- Verification: focused synthetic tests for default AVAudio timer-source publishing, C mixer sample-time-source publishing, trace source fields, resolver mapping, and trace summary published-vs-C-mixer deltas; manual launch/smoke verification for default backend selection, flagged C mixer selection, trace writing, Play/Stop, and unchanged tracker viewport behavior.
- Status: done.

### PR 2.7.11n — Runtime C Mixer Transient / Event-Burst Diagnostics
- Scope: add diagnostics-first evidence for rare opt-in runtime C mixer transients that do not reproduce in clean offline C mixer WAV renders. Report lower-threshold adjacent-sample jump counts, bounded top jumps/peaks with nearby order/row/tick context, same-frame event burst categories, voice counts before/after bursts, replacement ramp cleanup counters, epsilon-suppressed update correlation, and runtime headroom/epsilon policy breadcrumbs. Keep AVAudio as the default backend, keep the C mixer runtime opt-in only, avoid tracker viewport/parser changes, avoid new XM effects, and avoid broad C mixer DSP changes.
- Verification: synthetic runtime trace summary tests, focused runtime C mixer trace/counter tests, existing runtime/offline render tests, app build/test, Play/Stop smoke, local-only traces kept out of git, and no private/local module fixtures.
- Status: done.

### PR 2.7.11o — Runtime C Mixer Peak-Safe Headroom / Burst Transient Stabilization
- Scope: make the experimental runtime C mixer fixed default headroom slightly more conservative at `-12 dB`, preserve peak/clipping, lower-threshold jump, and same-frame burst diagnostics, and report whether the active runtime gain policy is default or an environment override. Keep AVAudio as the default backend, keep the C mixer runtime opt-in only, avoid tracker viewport/parser changes, avoid new XM effects, avoid broad C mixer DSP changes, and do not change offline render behavior.
- Verification: focused runtime C mixer policy/trace tests, synthetic hot-render clipping tests, existing runtime/offline render tests, app build/test, local-only traces kept out of git, and no private/local module fixtures.
- Status: done.

### PR 2.7.11p — Runtime C Mixer Live Output Capture / Offline WAV Comparison
- Scope: add an opt-in local-only capture path for the experimental runtime C mixer backend that records the post-runtime-gain runtime host output buffer into a bounded in-memory capture and writes a local WAV outside the audio callback, so live runtime output can be compared with clean offline C mixer WAV renders.
- Verification: focused synthetic capture configuration, buffer ordering, cap/truncation, WAV writer, trace-field, backend-selection, and render-invariance tests; existing runtime/offline render tests; app build/test; local-only traces and WAVs kept out of git; no default backend switch, tracker viewport changes, parser refactor, new XM effects, C mixer DSP semantic changes, or private/local module fixtures.
- Status: done.

### PR 2.7.11q — Runtime C Mixer Event-Burst / Voice Transition Stabilization
- Scope: use runtime live-output evidence to narrowly stabilize dense same-frame event bursts and sustained carried-voice order-boundary transitions in the experimental runtime C mixer backend. Align runtime same-frame adapter ordering with the offline C mixer frame boundary, expand burst diagnostics with deterministic event ordering and voice-count fields, and trace update-without-note association behavior without changing offline render behavior, tracker viewport behavior, parser architecture, C mixer default selection, or XM effect coverage.
- Verification: focused synthetic runtime C mixer tests for same-frame ordering, burst diagnostics, sustained carried-voice association, update-without-note application, exact sample-time event application, replacement ramp cleanup preservation, backend opt-in/default selection, runtime capture diagnostics, existing offline render/comparison tests, app build/test, local-only runtime captures kept out of git, and no private/local module fixtures.
- Status: done.

### PR 2.7.11r — Runtime / Offline Mismatch Window Correlation Diagnostics
- Scope: add diagnostics-only local tooling that correlates full or near-full runtime live-output captures against offline C mixer WAV renders, imports whole-song comparison worst windows, accepts explicit target windows, and connects each window to runtime trace event categories, same-frame bursts, sustained voice association, active/loaded voice ranges, cleanup/ramp evidence, gain/headroom normalization, best local alignment shift, and optional offline diagnostics JSON.
- Verification: synthetic WAV/JSONL/diagnostics tests for window metrics, amplitude-only mismatch, timing-shift mismatch, trace event categories, same-frame bursts, voice ranges, malformed inputs, deterministic JSON/Markdown output, existing runtime trace summary tests, existing audio comparison/discontinuity tests, app build/test, local-only full-song smoke with generated artifacts kept out of git, and no private/local module fixtures in automated tests.
- Status: done.

### PR 2.7.11s — Runtime C Mixer Event Burst / AVAudio Delivery Diagnostics Follow-Up
- Scope: keep the event-burst follow-up diagnostics-only after local capture comparison showed no material benefit from the attempted replacement-ramp state behavior change. Preserve runtime live-output capture and replacement burst diagnostics, add runtime output-host and hardware sample-rate/channel diagnostics, and use those fields to test whether remaining live GUI artifacts are downstream of the captured C mixer PCM.
- Verification: focused synthetic runtime C mixer tests for mixed burst ordering, replacement ramp state diagnostics, key-off/fadeout diagnostics, intended-frame note starts, channel preservation, global stop preservation, runtime headroom, exact sample-time event application, capture diagnostics, AVAudio graph trace fields, existing runtime/offline render tests, app build/test, local-only full or near-full runtime/offline capture comparison with generated artifacts kept out of git, and no private/local module fixtures in automated tests.
- Status: done.

### PR 2.7.11t — Transport Stop Position Preservation / Spacebar Playback Shortcut
- Scope: preserve the current playback/edit order-row when Stop is pressed and add a conservative plain Spacebar play/stop shortcut through the tracker grid focus path.
- Verification: focused synthetic transport tests for Stop preservation, play-after-stop start position, Spacebar stop/play behavior, backend selection defaults, opt-in C mixer behavior, and no pattern-editing mutation from Spacebar; manual local smoke with private/local modules kept out of git.
- Status: done.

### PR 2.7.11u — Runtime C Mixer Runtime Host Format / Device Sample-Rate Alignment
- Scope: align the experimental runtime C mixer host, C mixer render config, runtime capture, planned adapter event frames, and sample-time resolver with the output graph/device sample rate where practical. Keep `VTX_AUDIO_BACKEND=c_mixer` opt-in, keep AVAudioPlayerNode/AVAudioUnitVarispeed as default, leave offline render behavior unchanged, and add only local diagnostic override support through `VTX_C_MIXER_RUNTIME_SAMPLE_RATE`.
- Verification: focused synthetic tests for graph-aligned, fallback, and explicit runtime sample-rate policy; planned frame and sample-time resolver use of the selected runtime sample rate; capture sample-rate reporting; format conversion diagnostics for matching and mismatched rates; backend default/opt-in behavior; existing runtime capture/event/sample-time tests, offline render tests, audio comparison tests, app build/test, and local-only smoke artifacts kept out of git.
- Status: done.

### PR 2.7.11v — Runtime C Mixer AVAudio Callback Realtime Safety / I/O Buffer Diagnostics
- Scope: add diagnostics-first evidence for remaining live-only artifacts after clean offline C mixer renders and clean runtime captures. Report runtime host callback timing, render quantum budget, callback intervals, output-buffer fill/copy layout, scratch/capture/output hash comparisons, and local trace/capture/minimal-callback isolation flags. Keep `VTX_AUDIO_BACKEND=c_mixer` opt-in, keep AVAudioPlayerNode/AVAudioUnitVarispeed as default, leave offline rendering and C mixer DSP semantics unchanged, and avoid tracker viewport/parser/effect changes.
- Verification: focused synthetic tests for callback counters, output copy helpers, capture-vs-source summaries, env disable flags, backend default/opt-in behavior, existing runtime capture/sample-rate/sample-time tests, offline render tests, audio comparison tests, app build/test, local-only smoke artifacts kept out of git, and no private/local module fixtures.
- Status: done.

### PR 2.7.11w — Runtime C Mixer Render Callback Diagnostics Decoupling
- Scope: remove allocation-prone diagnostic bookkeeping from the experimental runtime C mixer callback by replacing callback-side diagnostic event collection with fixed-capacity buffers and counters, reporting diagnostic drops and try-lock failures, and keeping trace/capture serialization outside the callback. Keep `VTX_AUDIO_BACKEND=c_mixer` opt-in, keep AVAudioPlayerNode/AVAudioUnitVarispeed as default, leave offline rendering and C mixer DSP semantics unchanged, and avoid tracker viewport/parser/effect changes.
- Verification: focused synthetic tests for deterministic fixed-ring behavior, overflow/drop reporting, realtime-safe callback diagnostic fields, bounded capture behavior, disabled trace/capture modes, backend default/opt-in behavior, existing runtime capture/sample-rate/sample-time tests, offline render tests, audio comparison tests, app build/test, local-only smoke artifacts kept out of git, and no private/local module fixtures.
- Status: done.

### PR 2.7.11x — ADR: Alternative Runtime Output Host for C Mixer
- Scope: document why clean offline C mixer renders, clean runtime source captures, and AVAudioSourceNode output-copy verification leave the experimental SourceNode runtime delivery path suspect for remaining live-only artifacts, while keeping AVAudioPlayerNode/AVAudioUnitVarispeed as the default backend and keeping `VTX_AUDIO_BACKEND=c_mixer` experimental and opt-in.
- Verification: documentation-only review plus `scripts/check-files.sh`, `git diff --check`, and local-only path/module-name scan.
- Status: done.

### PR 2.7.11y — Runtime C Mixer CoreAudio/AUAudioUnit Output Host Spike
- Scope: implement a developer-only opt-in runtime output host for the C mixer, using a minimal CoreAudio DefaultOutput Audio Unit callback host, to test whether remaining live-only artifacts are caused by AVAudioEngine/AVAudioSourceNode delivery. Keep AVAudioPlayerNode/AVAudioUnitVarispeed as default, leave offline render behavior unchanged, avoid tracker viewport/parser/effect changes, and keep generated traces/captures/listening notes local-only.
- Verification: focused backend-selection, callback, capture, and default-preservation tests; existing runtime/offline render tests; app build/test; local-only A/B route/capture smoke with artifacts kept out of git and no private module fixtures in automated tests.
- Status: done.

### PR 2.7.11z — Runtime C Mixer Output Host Listening and Capture Comparison
- Scope: keep the CoreAudio DefaultOutput host experimental and run a diagnostics-first listening/capture path. Extend trace summaries with backend, host, callback, sample-rate/channel, capture, CoreAudio OSStatus, and song-end lifecycle fields, including capture seconds versus debug stop duration and planned song-end evidence.
- Verification: synthetic tests for backend default/opt-in selection, comparable trace summaries for both hosts, missing capture fields, capture-duration/playback-lifetime separation, debug stop reporting, runtime song-end lifecycle reporting, existing runtime/offline render tests, app build/test, local-only A/B smoke with generated artifacts kept out of git, and no private module fixtures in automated tests.
- Status: done.

### PR 2.7.11aa — Runtime C Mixer Song-End Stop / Tail Handling
- Scope: stop or silence the opt-in runtime C mixer host at the planned adapter song end plus a short runtime tail. Keep capture duration as capture-only diagnostics, keep debug stop as a playback stop, and leave the default AVAudio backend unchanged.
- Verification: focused synthetic runtime lifecycle tests for planned song end, optional tail behavior, capture duration independence, debug stop behavior, both C mixer runtime hosts, and unchanged offline render behavior.
- Status: done.

### PR 2.7.11ab — Deprecate AVAudioSourceNode C Mixer Backend / Prefer CoreAudio Experimental Host
- Scope: retire the AVAudioSourceNode-hosted runtime C mixer backend, map both `VTX_AUDIO_BACKEND=c_mixer` and `VTX_AUDIO_BACKEND=c_mixer_coreaudio` to the CoreAudio DefaultOutput Audio Unit host, preserve AVAudioPlayerNode/AVAudioUnitVarispeed as default, and keep offline C mixer rendering/export unchanged.
- Verification: backend selection tests, CoreAudio host lifecycle/capture/diagnostics tests, existing runtime/offline render tests, app build/test, audio comparison tests, file checks, local-only smoke with artifacts kept out of git, and no private module fixtures in automated tests.
- Status: done.

### PR 2.7.11ac — Runtime C Mixer CoreAudio Render Core Slimdown / Realtime Boundary Hardening
- Scope: simplify the preferred CoreAudio runtime C mixer hot path now that the SourceNode host is retired. Keep render/copy/counter updates inside one non-blocking render-core callback entry where practical, move SourceNode-era graph state out of the CoreAudio diagnostics path, preserve fixed-capacity callback diagnostics, and leave AVAudio default playback plus offline rendering unchanged.
- Verification: focused runtime render-core and CoreAudio callback diagnostics tests, existing backend selection/lifecycle/capture/runtime adapter/offline tests, app build/test, audio comparison tests, file checks, local-only smoke with artifacts kept out of git, and no private module fixtures in automated tests.
- Status: done.

### PR 2.7.11ad — Runtime C Mixer CoreAudio Host Hardening / Manual Corpus Pass
- Scope: harden the preferred CoreAudio DefaultOutput host with manual corpus listening/capture evidence while keeping the backend opt-in until runtime lifecycle, stability, and route/device behavior are proven.
- Verification: focused CoreAudio host lifecycle tests, route/device diagnostics, app build/test, and local-only long-run listening/capture evidence with artifacts kept out of git.
- Status: done.

### PR 2.7.11ae — Runtime C Mixer CoreAudio Callback Lock Contention / Output Delivery Follow-Up
- Scope: investigate and reduce CoreAudio callback lock contention after the host hardening corpus pass. Keep the callback non-blocking, avoid skipped audio on try-lock failure by reusing the last valid callback output when available, decouple diagnostic/follow publication from render-lock snapshots while the host is running, and add explicit lock, stale-output, skipped-audio, near-budget, callback-thread, and lifecycle-overlap counters. Keep the runtime C mixer opt-in, keep AVAudioPlayerNode/AVAudioUnitVarispeed as default, leave offline rendering and C mixer DSP unchanged, and avoid tracker viewport/parser/effect changes.
- Verification: focused synthetic callback lock-failure/lifecycle diagnostics tests, backend default/alias tests, existing runtime capture/diagnostics/song-end/offline render tests, app build/test, audio comparison tests, local-only smoke with generated artifacts kept out of git, and no private module fixtures in automated tests.
- Status: done.

### PR 2.7.11af — Runtime C Mixer CoreAudio Default / AVAudio Legacy Fallback
- Scope: make the CoreAudio DefaultOutput Audio Unit C mixer host the default runtime backend. Keep `VTX_AUDIO_BACKEND=c_mixer` and `VTX_AUDIO_BACKEND=c_mixer_coreaudio` as CoreAudio aliases, keep `VTX_AUDIO_BACKEND=av_audio` as an explicit legacy fallback, do not reintroduce AVAudioSourceNode, and leave offline rendering, C mixer DSP, parser architecture, tracker viewport behavior, runtime adapter semantics, gain/headroom policy, and song-end/tail policy unchanged.
- Verification: focused backend selection and factory trace tests, existing CoreAudio lifecycle/capture/diagnostics/song-end/offline render tests, app build/test, audio comparison tests, local-only smoke with generated artifacts kept out of git, and no private/local module fixtures in automated tests.
- Status: done.

### PR 2.7.11ag — Remove AVAudioPlayerNode Legacy Backend
- Scope: remove the AVAudioPlayerNode / AVAudioUnitVarispeed runtime backend now that the CoreAudio C mixer is the default runtime path. Keep `VTX_AUDIO_BACKEND=c_mixer` and `VTX_AUDIO_BACKEND=c_mixer_coreaudio` as CoreAudio aliases, treat `VTX_AUDIO_BACKEND=av_audio` as a retired value that falls back to the CoreAudio C mixer, do not reintroduce AVAudioSourceNode, and leave offline rendering, C mixer DSP, parser architecture, tracker viewport behavior, runtime adapter semantics, gain/headroom policy, and song-end/tail policy unchanged.
- Verification: focused backend selection and factory trace tests, existing CoreAudio lifecycle/capture/diagnostics/song-end/offline render tests, app build/test, audio comparison tests, parser/golden tests, local-only smoke with generated artifacts kept out of git, and no private/local module fixtures in automated tests.
- Status: done.

### PR 2.7.11ah — Runtime Diagnostics Cleanup / Remove Obsolete Backend Debugging
- Scope: remove current-runtime trace fields, tests, and docs that only described the retired AVAudioPlayerNode or AVAudioSourceNode-era graph while preserving CoreAudio C mixer host, callback, route/device, capture, song-end/tail, and offline render/export diagnostics. Keep the trace summary tolerant of older local trace files where cheap.
- Verification: focused backend selection and factory trace tests, trace-summary tests for current CoreAudio traces and missing retired fields, existing CoreAudio lifecycle/capture/diagnostics/song-end/offline render tests, app build/test, audio comparison tests, parser/golden tests, local-only smoke with generated artifacts kept out of git, and no private/local module fixtures in automated tests.
- Status: done.

### PR 2.7.11ai — XM Effect Coverage Audit / Local Missing-Effect Target Selection
- Scope: add local-only effect coverage summary tooling for bounded offline diagnostics JSON and runtime C mixer traces, report detected/applied/deferred/unsupported/no-op command buckets with first source coordinates and unresolved key-off/no-active breakdowns, run local reference-module/corpus diagnostics outside git, and recommend one evidence-based next effect implementation target.
- Verification: synthetic JSON/JSONL summary tests for deterministic counts, first coordinates, empty diagnostics, unknown high effect bytes, volume-column commands, no-op/effect-memory buckets, and existing runtime/offline/audio comparison checks; local private modules and generated artifacts remain under ignored paths.
- Status: done.

### PR 2.7.11aj — Minimal 4xy Vibrato Foundation
- Scope: implement only the smallest useful XM `4xy` vibrato behavior through the bounded/offline C mixer adapter and runtime C mixer adapter plan where applicable, preserving existing parser architecture, tracker viewport behavior, backend defaults, and C mixer DSP semantics unless a narrow pitch-update diagnostic/application hook is required.
- Verification: deterministic hand-built `PlaybackSong` tests for vibrato speed/depth decoding, tick-phase pitch modulation, zero-parameter/effect-memory behavior as scoped, interaction with current linear-frequency pitch mapping, windowed carryover, runtime trace fields if bridged, and existing bounded render/audio comparison tests; no private/local module fixtures.
- Status: done.

### PR 2.7.11ak — Minimal E5x Set Finetune Foundation
- Scope: implement only same-cell note `E5x` set-finetune through the shared bounded/offline and runtime C mixer adapter sample-step path, with no broad finetune memory and no unrelated E-command behavior.
- Verification: synthetic fixtures for detection, same-cell sample-step changes, deterministic `E50`/`E5F` behavior, no-note deferral, no leakage into later notes, runtime adapter metadata, windowed render determinism, and explicit non-goal coverage for `E2x`, `EAx`, and `EBx`; local-only corpus smoke artifacts stay out of git.
- Status: done.

### PR 2.7.11al — Minimal E2x Fine Portamento Down
- Scope: implement only XM `E2x` fine portamento down through the shared bounded/offline and runtime C mixer adapter sample-step path, applying one deterministic row-level linear-period increase for active voices and folding same-cell note `E2x` into the triggered note's initial playback step. `E20` remains effect-memory-deferred and `E1x`, `EAx`/`EBx`, `6xy`, broad effect memory, parser changes, tracker viewport changes, and backend default changes remain out of scope.
- Verification: synthetic fixtures for detection/counting, active-voice sample-step changes, distinct `E21`/`E2F` behavior, `E20` no-op diagnostics, no-active-voice diagnostics, no retriggering, same-cell note policy, runtime adapter metadata, windowed render determinism, explicit non-goal coverage for `E1x`/`EAx`/`EBx`, existing render/effect-coverage tests, and local-only corpus smoke artifacts kept out of git.
- Status: done.

### PR 2.7.11am — Minimal EAx / EBx Fine Volume Slides
- Scope: implement only XM `EAx` fine volume slide up and `EBx` fine volume slide down through the shared bounded/offline and runtime C mixer adapter gain path, applying one deterministic row-level clamped channel-volume adjustment for nonzero amounts. `EA0`/`EB0` remain no-op/effect-memory deferred, and `E1x`, `6xy`, broad effect memory, parser changes, tracker viewport changes, and backend default changes remain out of scope.
- Verification: synthetic fixtures for detection/counting, active-voice gain changes, distinct `EA1`/`EAF` and `EB1`/`EBF` behavior, `EA0`/`EB0` no-op diagnostics, no-active-voice diagnostics, no retriggering, same-cell note policy, runtime adapter metadata, windowed render determinism, existing render/effect-coverage tests, and local-only corpus smoke artifacts kept out of git.
- Status: done.

### PR 2.7.11an — Minimal 6xy Vibrato + Volume Slide
- Scope: implement only XM effect-column `6xy` through the shared bounded/offline and runtime C mixer adapter paths, reusing prior nonzero `4xy` channel vibrato settings for sample-step updates and the existing row-level volume-slide/gain path. `600`, missing vibrato memory, volume-column vibrato, waveform controls, `E1x`, broad effect memory, parser changes, tracker viewport changes, and backend default changes remain out of scope.
- Verification: synthetic fixtures for detection/counting, active-voice sample-step and gain changes, `600` no-op diagnostics, no-active-voice diagnostics, no retriggering, same-cell note policy, runtime adapter metadata, split/windowed render determinism, existing render/effect-coverage tests, and local-only corpus smoke artifacts kept out of git.
- Status: done.

### PR 2.7.11ao — XM Effect Memory Foundation
- Scope: add explicit per-channel Swift adapter/runtime-planning effect memory for already-supported `9xx`, `4xy`, and conservative `6xy` cases only. `900` reuses prior nonzero sample-offset memory, `400` and single-zero `4xy` nibbles reuse prior vibrato memory, and `600` can replay prior vibrato memory without broad volume-slide memory. `E1x`, `E0x`, `0xy`, traversal commands, parser changes, tracker viewport changes, and backend default changes remain out of scope.
- Verification: synthetic fixtures for memory store/reuse/missing cases, per-channel isolation, direct-start determinism, windowed render carryover, runtime adapter metadata, diagnostics JSON/effect-coverage counts, existing runtime/offline render tests, and local-only corpus smoke artifacts kept out of git.
- Status: done.

### PR 2.7.11ap — Minimal E1x Fine Portamento Up
- Scope: implement only XM `E1x` fine portamento up through the shared bounded/offline and runtime C mixer adapter sample-step path, applying one deterministic row-level linear-period decrease for active voices and folding same-cell note `E1x` into the triggered note's initial playback step. `E10` remains effect-memory-deferred, and `E0x`, `0xy`, traversal commands, broad effect memory, parser changes, tracker viewport changes, and backend default changes remain out of scope.
- Verification: synthetic fixtures for detection/counting, active-voice sample-step changes, distinct `E11`/`E1F` behavior, `E10` no-op diagnostics, no-active-voice diagnostics, no retriggering, same-cell note policy, runtime adapter metadata, windowed render determinism, existing render/effect-coverage tests, and local-only corpus smoke artifacts kept out of git.
- Status: done.

### PR 2.7.11aq — XM Effect Coverage Refresh After E1x
- Scope: diagnostics-only refresh of the full mapped local XM corpus after the `4xy`, `E5x`, `E2x`, `EAx`/`EBx`, `6xy`, targeted effect-memory, and `E1x` passes. This updates the local summary helper recommendation only; it does not add XM effect behavior, parser changes, tracker viewport changes, backend changes, or committed private artifacts.
- Findings: the post-`E1x` local-only pass covered 26 anonymized inputs and reported 222,402 detected commands, 214,105 applied, 187 deferred, 172 unsupported, 8,125 no-op/effect-memory deferred, 3,316 effect-memory reuses, and 1 missing effect-memory case. Remaining unsupported concrete buckets were `E0x` filter toggle (72, limited usefulness), `0xy` arpeggio (53, strong), `Dxx` pattern break (31, moderate traversal), `E4x` vibrato control (9, limited), `E6x` pattern loop (6, moderate traversal), and `Bxx` position jump (1, moderate traversal). The dominant implemented-effect memory buckets were zero-parameter `2xx` (653) and `1xx` (268), while `900` sample-offset memory had only one missing case.
- Verification: full local diagnostics and public-safe summaries were generated under `/tmp`; generated WAV/JSON/Markdown artifacts and private modules stayed out of git. `python3 -m unittest tools/audio_compare_tests.py`, `./scripts/check-files.sh`, `git diff --check`, and the private-path hygiene scan passed.
- Status: done.

### PR 2.7.11ar — 1xx/2xx Portamento Effect Memory Expansion
- Scope: add only zero-parameter memory replay for already-supported `1xx`/`2xx` portamento slides. `100` and `200` reuse prior nonzero same-family per-channel memory when available, missing memory remains diagnosed, and `E0x`, `0xy`, traversal behavior, broad effect memory, parser changes, tracker viewport changes, and backend changes remain out of scope.
- Verification: synthetic fixtures for per-channel memory store/reuse/missing cases, direct-start determinism, windowed render carryover, runtime adapter metadata, diagnostics/effect-coverage counts, existing render/effect-coverage tests, and local-only corpus smoke artifacts kept out of git.
- Status: done. Recommended next effect PR: `0xy` arpeggio unless refreshed local evidence points more strongly at traversal.

### PR 2.7.11as — XM Effect Coverage Refresh After Portamento Memory
- Scope: diagnostics-only refresh of the full mapped local XM corpus after the `1xx`/`2xx` portamento memory expansion. This updates the summary recommendation heuristic so limited-usefulness `E0x` filter-toggle evidence does not crowd out the largest useful concrete unsupported effect; it does not add XM effect behavior, parser changes, tracker viewport changes, backend changes, or committed private artifacts.
- Findings: the post-portamento-memory local-only pass covered 26 anonymized inputs and reported 222,402 detected commands, 214,963 applied, 187 deferred, 172 unsupported, 7,267 no-op/effect-memory deferred, 4,174 effect-memory reuses, and 1 missing effect-memory case. Remaining unsupported concrete buckets were `E0x` filter toggle (72, limited usefulness), `0xy` arpeggio (53, strong), `Dxx` pattern break (31, moderate traversal), `E4x` vibrato control (9, limited), `E6x` pattern loop (6, moderate traversal), and `Bxx` position jump (1, moderate traversal). The post-`1xx`/`2xx` memory residuals are no longer implementation recommendations: zero-parameter `2xx` has 609 memory reuses and 44 no-active/no-op cases, zero-parameter `1xx` has 249 memory reuses and 19 no-active/no-op cases, `4xy` has 595 memory reuses with no missing cases, `6xy` has 36 memory reuses with no missing cases, and `900` sample-offset memory still has one missing/no-op case.
- Verification: full local diagnostics and public-safe summaries were generated under `/tmp`; generated WAV/JSON/Markdown artifacts and private modules stayed out of git. Three anonymized inputs needed the renderer's playable order count rather than raw `mc_dump` order-table length, which is tracked as a separate testing/tooling follow-up below.
- Status: done. Recommended next effect PR: `Minimal 0xy Arpeggio Foundation`.

### PR 2.7.11at — Bounded XM Diagnostics Playable-Order Count Alignment
- Scope: surgically align local corpus diagnostics tooling around the renderer/playback builder's playable order count so full-corpus test runs do not have to manually adjust modules where raw order-table length exceeds the playable order range. Keep this diagnostics/testing-only: no XM effect implementation, no parser compatibility claim, no tracker viewport changes, and no private module fixtures.
- Verification: synthetic metadata/playback-builder fixtures for trailing or otherwise non-playable order entries, `vtx_render_bounded_xm` order-range validation coverage, and a local-only anonymized corpus smoke confirming the previously affected labels can run without manual order-count subtraction.
- Status: queued testing/tooling follow-up.

### PR 2.7.11au — Minimal 0xy Arpeggio Foundation
- Scope: implement only XM effect-column `0xy` arpeggio through deterministic Swift adapter sample-step scheduling for bounded offline C mixer renders and CoreAudio C mixer runtime adapter events. `000` remains a no-op; arpeggio effect memory, `E0x`, traversal commands, vibrato control, parser changes, tracker viewport changes, backend default changes, and retired AVAudio backends remain out of scope.
- Diagnostics: bounded JSON now reports `arpeggio_effects` / `arpeggio_0xy_effects`, semitone offsets, applied/no-active/deferred status, and scheduled sample-step update counts. Runtime adapter plans tag note triggers and step updates with `arpeggio_0xy` metadata.
- Status: done. Follow-up implemented in PR 2.7.11av; `E0x` remains deferred/limited-usefulness unless refreshed local evidence changes the ordering.

### PR 2.7.11av — Focused Dxx/Bxx/E6x Traversal Foundation
- Scope: implement only deterministic first-pass traversal planning for XM `Dxx` pattern break, `Bxx` position jump, and `E6x` pattern loop in the Swift adapter/runtime planning layer shared by bounded/offline C mixer renders and CoreAudio C mixer runtime event plans. `Dxx` uses XM-style BCD row targets, same-row `Bxx` + `Dxx` jumps to the `Bxx` order using the `Dxx` row target, `E6x` loop markers/counts are scoped per channel/order/pattern, missing `E60` starts are diagnosed without inventing a loop, and traversal is bounded by a deterministic row guard.
- Diagnostics: bounded JSON now reports `traversal_summary`, `traversal_effects`, traversal path length, stop reason, guard hits, applied counts, source coordinates, target order/pattern/row, invalid/out-of-range targets, missing loop starts, loop counts, and loop-limit hits. The effect coverage path now treats `Dxx`/`Bxx`/`E6x` as applied or explicit safe diagnostics instead of broad unsupported traversal, while `EEx` and `E0x` remain deferred/unsupported.
- Status: done. Recommended next effect PR: residual effect classification and `E0x` deferral cleanup, unless refreshed local evidence points at a higher-value remaining bucket.

### PR 2.7.11aw — XM Effect / Parity Coverage Refresh After 3xx Gain-State Fix
- Scope: diagnostics-only refresh of the full mapped local XM corpus after the focused `xm-corpus-025` same-cell `3xx` instrument/default-volume gain-state fix. Keep this to local bounded diagnostics, public-safe anonymized reporting, and next-target selection; do not add XM effect behavior, parser changes, tracker viewport changes, backend changes, or committed private artifacts.
- Findings: the post-`3xx` gain-state local-only pass covered 26 anonymized inputs and reported 222,392 detected commands, 215,060 applied, 96 deferred, 81 unsupported, 7,250 no-op/effect-memory-deferred, 4,174 effect-memory reuses, and 1 missing effect-memory case. Remaining unsupported/deferred buckets were `E0x` filter toggle (72, limited usefulness), `E4x` vibrato control (9, concrete follow-up), and `EDx` note delay no-note cases (15 deferred plus 1 out-of-row no-op). `Dxx` traversal had 30 detected with 29 applied and 1 out-of-range safe diagnostic, `E6x` had 28 traversal records, no `Bxx` or `EEx` occurrences remained in the refreshed selected traversal path, volume-column vibrato/vibrato-speed did not appear, and `900`/`4xy`/`6xy`/`1xx`/`2xx` memory residuals were covered or no-active/no-op classifications except one missing `900` case.
- Focused findings: `xm-corpus-025` order 1 / pattern 7 / channel 5 rows `0x00...0x3F` still show same-cell `3xx` instrument state updates with no sample-position resets and no volume-column set-volume rows missing active-voice gain updates. A local optional MikMod/VTX comparison using simple `scripts/audio-compare.py` did not reproduce the earlier approximately 0.929 focused correlation: the auto-headroom first-30-second comparison reported 0.694 normalized correlation, while a trimmed order 1 / pattern 7 / rows `0x00...0x3F` segment reported 0.805. Treat those WAV metrics as local evidence only and reproduce the earlier comparison settings before changing playback behavior from that signal.
- Report: see `docs/reports/xm-coverage-refresh-after-3xx-gain-state-fix.md` for the public-safe summary. Full generated WAV/JSON/Markdown/log artifacts stayed under `/tmp`.
- Verification: local diagnostics generated under `/tmp`; private modules and the local label map stayed out of git. Recommended next PR: a focused `E4x` vibrato-control follow-up unless the maintainer prefers another diagnostics-only residual classification pass.
- Status: done.

### PR 2.7.11ax — Focused E4x Vibrato Control
- Scope: implement only XM `E4x` vibrato-control state in the Swift adapter/runtime planning layer shared by bounded/offline C mixer renders and CoreAudio C mixer runtime event planning. `E4x` stores supported per-channel sine/default, ramp-down, square, and deterministic-random waveform state for later `4xy`/`6xy` vibrato rows, emits no direct audio events, and leaves unsupported control values explicitly deferred.
- Diagnostics: bounded JSON now reports `vibrato_control_effects`, `e4x_vibrato_control_*` render counters, waveform/control values, stored/applied versus unsupported-waveform statuses, source coordinates, and later `4xy`/`6xy` waveform source fields. `E0x`, volume-column vibrato, new traversal behavior, parser changes, tracker viewport changes, C mixer DSP changes, backend default changes, and retired AVAudio paths remain out of scope.
- Status: done. Recommended next PR: refreshed residual classification focused on the now-small remaining unsupported/deferred buckets, `E0x` deferral documentation, or reference-render parity work.

### PR 2.7.11ay — XM Final Effect Residual Classification
- Scope: diagnostics-only refresh of the full mapped local XM corpus after the focused `E4x` vibrato-control pass. Keep this to compact local effect-coverage export, public-safe anonymized reporting, and next-target selection; do not add XM effect behavior, parser changes, tracker viewport changes, backend changes, C mixer DSP changes, or committed private artifacts.
- Findings: the final local-only pass covered 26 anonymized inputs and reported 904,704 detected commands, 865,829 applied, 87 deferred, 72 unsupported, 38,802 no-op/effect-memory-deferred, 4,174 effect-memory reuses, and 1 missing effect-memory case. The only remaining unsupported concrete bucket is `E0x` filter toggle with 72 deferred/unsupported occurrences, still classified as limited-usefulness. The previous `E4x` residual is covered: 9 `E4x` commands were detected and stored/applied, all observed as `E41`, with no `E44...E4F` residuals. `Dxx`/`Bxx`/`E6x` traversal is applied or safe out-of-range, `EDx` residuals are no-note/out-of-row, `900` has one missing-memory no-op, `1xx`/`2xx`/`3xx`/`ECx` residuals are no-active/no-target/out-of-row classifications, and volume-column vibrato/vibrato-speed/tone-portamento were not observed in the refreshed summary.
- Report: see `docs/reports/xm-final-effect-residual-classification.md` for the public-safe summary.
- Verification: local compact effect-coverage diagnostics generated under `/tmp`; private modules and the local label map stayed out of git. Recommended next PR: document `E0x` filter toggle as intentionally deferred, then move to reference-render parity work.
- Status: done.

### PR 2.7.11az — Real-Module Loop Endpoint Correctness Hardening
- Scope: fix only the C mixer forward-loop endpoint/sample-position boundary found by synthetic microfixtures: imported runtime positions at or beyond the exclusive loop end wrap to loop start with fractional overshoot preserved, and an exact initial source offset at the exclusive end starts at loop start instead of reading the first tail frame. Preserve existing offset-after-loop tail-read behavior, ping-pong behavior, no-loop behavior, runtime backend defaults, parser architecture, tracker viewport behavior, gain/headroom policy, and envelope/fadeout behavior.
- Verification: synthetic C mixer microfixtures for exclusive forward loop ends, no duplicated endpoint, fractional overshoot, loop-boundary interpolation, step greater than loop length, initial offset inside the loop, split render determinism, and existing forward-loop/ping-pong/no-loop regressions. Local-only anonymized reference checks kept generated WAV/JSON/Markdown artifacts under `/tmp`; the loop-heavy and envelope-heavy validation renders were byte-identical before and after this endpoint fix, with no observed improvement to the local reference mismatch.
- Status: done. Recommended next parity PR: period/sample-step conversion evidence for loop-heavy envelope-disabled material, with a separate envelope/key-off/fadeout timing pass for envelope-heavy material.

### PR 2.7.11ba — Period / Sample-Step Conversion Parity Investigation
- Scope: diagnostics-first investigation of whether remaining reference-render mismatches are caused by XM note/period/frequency/sample-step conversion. Extend the local correlation report with windowed active-voice period/sample-step evidence, including effective note, relative note, finetune, sample base/output rates, linear period/frequency, sample step, source position, loop mode, and scheduled sample-step updates near worst mismatch windows. Do not change playback behavior unless a tiny formula bug is proven by synthetic tests.
- Findings: current local evidence did not prove a tiny behavior fix. The loop-heavy envelope-disabled target remains compatible with a pitch/phase/loop-speed class of mismatch, while the envelope-heavy target remains confounded by envelope/key-off/fadeout behavior. Sample base rate is fixed at 8363 Hz in the current adapter diagnostics, linear-table status is consistently applied for the inspected local targets, and observed tone-portamento/sample-step update timing did not isolate a single broken formula.
- Verification: synthetic audio-correlation tests cover the new period/sample-step report section and missing optional fields. Local anonymized renders, reference comparisons, diagnostics JSON, and Markdown reports stayed under `/tmp` and out of git.
- Status: diagnostics-only. Recommended next parity PR: a narrowly tested Linear Period Formula Parity Fix or Relative Note / Finetune Sample-Step Fix if independent expected-value tests identify an exact formula delta; otherwise prioritize Envelope / Key-Off / Fadeout Timing Parity for envelope-heavy material.

### PR 2.7.11bb — Linear Period Formula / Sample Base Rate Parity Audit
- Scope: expected-value audit of the Swift adapter/runtime planning layer XM linear-period path: note + relative note, finetune and `E5x`, linear period/frequency, fixed 8363 Hz sample-base anchor, output-rate sample step, and tone-portamento targets. Do not change C mixer DSP, runtime backend defaults, tracker viewport code, parser architecture, envelopes/fadeout, gain policy, or unsupported effects.
- Findings: the FT2 linear-period and frequency equations match the current VTX formula, and the fixed 8363 Hz value is the XM linear-table C-4 base-frequency anchor rather than a parsed per-sample rate. The proven bug was the adapter clamping `note + relativeNote` to pattern note values `1...96`; FT2 applies relative note to a zero-based real-note range `0...118`, so high transposed samples could be under-pitched.
- Verification: synthetic app tests cover C-0, C-1, C-4, C-5, relative note -12/0/+12, high relative-note real-note clamping, negative/positive finetune, `E5x` override, 44.1 kHz and 48 kHz sample steps, and tone-portamento period targets. Local-only anonymized loop-heavy diagnostics stayed under `/tmp`; inspected mismatch windows did not contain out-of-range relative-note cases, so no reference-correlation improvement was attributed to this fix.
- Status: done. Recommended next parity PR: Envelope / Key-Off / Fadeout Timing Parity for envelope-heavy material, or Gain/Panning Math Parity if refreshed loop-heavy comparisons still show pitch-independent phase or level mismatch.

### PR 2.7.11bc — Envelope / Key-Off / Fadeout Timing Parity Investigation
- Scope: diagnostics-first investigation of whether remaining reference-render mismatches are caused by XM volume-envelope, note-off/key-off, and fadeout timing in the Swift adapter/runtime planning layer and C mixer render path. Add public-safe diagnostics for mapped envelope points, envelope position/value/segment snapshots, sustain/loop/key-on state, fadeout value, final voice gain, and per-window audible-envelope counts. Do not change envelope/fadeout behavior unless a tiny bug is proven by synthetic tests.
- Findings: current C mixer behavior is frame-based after the Swift adapter maps XM envelope ticks to output-frame positions. Key-off is applied at the scheduled frame before mixing that frame, sustain holds while key-on, envelope loops apply while key-on, and fadeout decrements after each released frame. Local `xm-corpus-011` Renoise comparison remains a broad mismatch with envelope/key-off/fadeout evidence, but the new probe snapshots show the top windows are dominated by sustain-held audible envelope voices rather than a clear fadeout-start bug. Local `xm-corpus-025` control windows have zero envelope-enabled events and zero key-offs, so they remain outside this PR's target.
- Verification: synthetic diagnostics tests cover the new envelope snapshot fields and missing optional correlation fields. Local anonymized renders, Renoise comparisons, diagnostics JSON, and Markdown reports stayed under `/tmp` and out of git.
- Status: diagnostics-only. Recommended next parity PR: Volume Envelope Tick-Clock / Sustain Timing Policy, with Key-Off / Fadeout Scaling Parity and Gain/Panning Math Parity kept separate until expected-value tests isolate those paths.

### PR 2.7.11bd — Offline Window Same-Channel Voice Replacement Parity
- Scope: align bounded/full and row-windowed offline C mixer voice lifetime with runtime CoreAudio C mixer same-channel note replacement semantics. Replacing notes now schedule a deterministic 32-frame gain-to-zero ramp for the older same-channel voice and retire it after ramp completion; in-flight replacement ramps are carried across row-window boundaries. No new XM effects, parser changes, tracker viewport changes, runtime backend default changes, gain/headroom changes, or envelope timing policy changes are included.
- Findings: runtime C mixer replacement already ramped older channel-tagged voices immediately, but offline bounded/windowed renders pre-scheduled all note voices and relied on window-boundary latest-event pruning. Dense windows could therefore keep too many audible same-channel voices until the next boundary. Synthetic fixtures now prove full/windowed determinism and cap same-channel overlap at one active voice plus one bounded replacement ramp.
- Diagnostics: bounded diagnostics JSON now reports `same_channel_voice_lifetime`, active/loaded voices by source channel, replacement start/completion counts, overlap frames, max voices per source channel, old-voice kept reasons, ramp duration, and window-boundary prune count. Runtime adapter event plans tag repeated same-channel note triggers with `replacement`.
- Verification: synthetic C mixer and playback adapter fixtures cover repeated notes, envelope-enabled replacements, full/windowed equivalence, same-cell `3xx` no-retrigger, plain-note replacement after `3xx`, and runtime/offline event category agreement. Local anonymized safe-level private-module candidate/reference renders stayed under `/tmp`; they showed replacement overlap is bounded, replacement starts/completions match, and window-boundary prune count is zero.
- Status: done as an offline renderer correctness and reference-harness fix. No pre-fix safe-level baseline was generated, so this PR does not claim a proven reference-correlation improvement. Recommended next parity PR: gain/headroom-normalized level behavior or a reference-backed volume-envelope tick-clock experiment, keeping key-off/fadeout scaling and gain/panning math as separate expected-value targets.

### PR 2.7.11be — Gain / Panning Math Parity Investigation
- Scope: diagnostics-first investigation of whether remaining reference-render mismatch evidence points at gain normalization/order, channel/global volume scaling, envelope/fadeout multiplication, panning law, stereo placement, or remaining waveform/timing issues. Do not change C mixer DSP, runtime backend defaults, tracker viewport behavior, parser architecture, period/sample-step formulas, loop endpoints, or XM effect coverage.
- Diagnostics: `scripts/audio-compare.py` now reports stereo-as-is, mono-summed, left-only, right-only, side-channel, and gain-normalized comparison modes plus per-window left/right/mono/side metrics. The local correlation report now summarizes worst-window active voice final-gain and pan distributions and shows the current C mixer linear pan law left/right gain ranges.
- Verification: synthetic audio comparison and correlation tests cover the new fields and missing optional diagnostics. Private/local modules and generated WAV/JSON/Markdown artifacts remain local-only and out of git.
- Status: diagnostics-only unless a later focused PR proves a tiny expected-value gain or panning bug.

### PR 2.7.11bf — XM Gain Multiplication / Normalization Parity Fix
- Scope: narrowly audit XM sample, channel, global-volume, envelope, and fadeout multiplication across the Swift adapter and C mixer render path. Do not change panning law, period/sample-step formulas, loop behavior, runtime backend defaults, parser architecture, tracker viewport behavior, or retired AVAudio backends.
- Findings: the gain policy is `sampleVolume * channelVolume/64 * globalVolume/64`, followed by C mixer `volumeEnvelope * fadeout` at render time before panning. The C mixer was already applying gain, envelope, and fadeout once. The proven bug was adapter-side support for `Hxy` global-volume slides without matching `Gxx` set-global-volume updates; bounded/offline and runtime C mixer plans now apply clamped `Gxx` row-level global volume and active voice gain updates.
- Verification: synthetic expected-value tests cover full and half sample/channel/global volume, combined sample/channel/global/envelope, C mixer envelope/fadeout multiplication, and `Gxx` active/future voice gain updates. Local-only 48 kHz runtime CoreAudio captures and offline C mixer renders stayed under `/tmp`; runtime/offline correlation was effectively 1.0 for the primary target and a secondary envelope-heavy window.
- Status: done. Primary local reference metrics did not materially improve because the primary target contained no `Gxx` events; recommended next parity PR remains focused sample-step/loop/interpolation or envelope tick-clock work based on mismatch-window evidence, not panning.

### PR 2.7.11bg — xm-corpus-025 Sample-Step / Loop / Timing Focused Window Parity
- Scope: diagnostics-first investigation of known envelope-disabled `xm-corpus-025` mismatch windows, focused on row/tick mapping, active voices, source sample position, sample-step updates, loop crossings, tone-portamento timing, sample offsets, same-channel replacement, gain/pan updates, traversal rows, and same-frame event groups. Do not implement new XM effects, change C mixer DSP/gain/panning policy, alter runtime backend defaults, modify tracker viewport code, or refactor parser architecture.
- Diagnostics: `scripts/focused-window-voice-timeline.py` consumes bounded offline diagnostics JSON plus explicit `--window START:END` values or comparison worst windows, and reports focused voice timelines with replacement-ramp-aware active voice lifetimes.
- Findings: local focused windows showed repeated dense same-frame row events, same-channel replacement ramps, gain updates, and looped sample-position evolution. Early known windows overlapped `3xx` tone-portamento tick-1 sample-step updates; later worst windows had fewer or no sample-step updates but still showed local alignment shifts against references. No tiny sample-step, loop endpoint, sample-offset, replacement, event-ordering, or row-boundary bug was proven.
- Verification: synthetic script tests cover focused row/tick mapping, active voice lifetime, loop/source-position estimates, tone-portamento sample-step updates, sample offsets, replacements, same-frame groups, Markdown output, and missing optional fields. Local private-module WAV/JSON/Markdown artifacts stayed under `/tmp` and out of git.
- Status: diagnostics-only. Recommended next parity PR: reference-backed row/tick boundary frame rounding or sample-step update frame timing experiment for the same focused windows; move to envelope/key-off/fadeout only for envelope-heavy targets.

### PR 2.7.11bh — Row/Tick Boundary Frame Rounding / Sample-Step Timing Audit
- Scope: diagnostics-first audit of adapter/runtime row/tick frame mapping, C mixer event application timing, and `3xx` tone-portamento sample-step update frames for `xm-corpus-025` focused windows. No new XM effects, backend changes, tracker viewport changes, parser changes, gain/pan policy changes, loop endpoint changes, or broad DSP rewrites.
- Findings: the current adapter computes `framesPerTick = sampleRate * 2.5 / BPM`, accumulates exact fractional row starts, floors row/tick boundaries, and applies scheduled C mixer state events before rendering the scheduled frame. A local ft2-clone render is now the primary FT2-style reference for `xm-corpus-025`, with MikMod and Renoise retained as secondary references. VTX is closer to ft2-clone than to MikMod or Renoise, and the remaining largest ft2-clone windows are mostly zero-shift, high-correlation amplitude/timbre differences around loop crossings and occasional replacement/gain events. This did not prove a consistent sample-step timing, event-ordering, or row-boundary audio-render fix.
- Change: bounded diagnostics now record explicit row/tick mapping and event-application timing policies, focused-window Markdown reports include sample-step and `3xx` timing tables, and runtime planning diagnostics use the same accumulated exact row-start math as scheduled adapter events.
- Verification: synthetic tests cover diagnostics JSON timing-policy fields, focused-window optional-field handling and timing tables, and fractional row-start runtime planned-frame mapping.
- Status: narrow diagnostics/planning parity fix only; reference correlation is expected to stay effectively unchanged. Recommended next parity PR: use ft2-clone as the preferred XM reference for `xm-corpus-025` and compare C mixer resampler/timbre plus per-voice level normalization evidence before changing gain/export policy.

### PR 2.7.11bi — ft2-clone Amplitude / Timbre Parity Investigation
- Scope: diagnostics-first comparison tooling and local `xm-corpus-025` ft2-clone evidence. No C mixer DSP, gain math, panning law, sample-step behavior, XM effect behavior, runtime backend, tracker viewport, or parser architecture changes.
- Findings: `scripts/audio-compare.py` can now read IEEE float WAV format code `3` directly, so ft2-clone 32-bit float exports no longer require temporary PCM conversion. Direct float comparison matches the prior converted-reference result: correlation about `0.939009`, global gain-normalized RMS about `0.036238`, and zero best local shift in the top windows. The highest-correlation windows are mostly scalar amplitude differences, while lower-correlation worst windows show ft2-clone retaining more high-frequency-proxy/transient energy than VTX.
- Change: audio comparison JSON/Markdown now reports sample format/code, per-window gain-normalized RMS difference, mono high-frequency proxy, zero-crossing rate, transient derivative RMS, and residual shape evidence. Public docs record ft2-clone as the preferred FT2-style reference when an export is available.
- Verification: synthetic audio comparison tests cover 32-bit float WAV reading, float peak/RMS, float candidate/reference comparison, sample-rate mismatch rejection, unchanged PCM16 scaling, and timbre metrics. Local private WAV/JSON/Markdown artifacts stayed under `/tmp` and out of git.
- Status: diagnostics/tooling only. Recommended next parity PR: C Mixer Resampler / Interpolation Timbre Parity microfixtures first; keep Sample/Instrument Volume Normalization Edge Case as the next level-focused alternative if timbre microfixtures do not reproduce the residual.

### PR 2.7.11bj — C Mixer Resampler / Interpolation Timbre Diagnostics
- Scope: diagnostics/tooling-only C mixer sample interpolation/resampler timbre investigation for `xm-corpus-025`, with synthetic microfixtures only in automated tests. No new XM effects, parser changes, tracker viewport changes, gain policy changes, panning law changes, period/sample-step changes, loop endpoint behavior changes, runtime backend changes, or C mixer behavior changes.
- Findings: VTX's C mixer uses always-enabled floor-index linear interpolation: source index is `floor(sample_position)`, fraction is `sample_position - floor(sample_position)`, signed float samples are blended as current/next without sign-specific branching, no-loop next samples clamp to the final frame, forward-loop interpolation wraps from the exclusive loop end back to loop start, and ping-pong interpolation follows the reflected playback position. Targeted local ft2-clone inspection found configurable disabled, linear, cubic, SINC8, and SINC16 interpolation modes; the inspected configuration path appears to use SINC8 as the default or fallback, plus separate volume ramping behavior.
- Local evidence: the current auto-headroom `xm-corpus-025` comparison against the local ft2-clone 48 kHz float reference was zero-shift in the top windows, with correlation about `0.922506` and global gain-normalized RMS about `0.039823` for the PCM16 VTX export. Highest-correlation windows mostly collapsed under local scalar normalization, while lower-correlation windows retained residuals where ft2-clone had substantially higher high-frequency/transient proxy energy. No point-sampling fallback, sample-step update timing, loop-boundary, ping-pong turnaround, panning, gain-policy, parser, or tracker-viewport bug was proven.
- Change: bounded render diagnostics now report a structured `sample_interpolation_kernel`; `scripts/audio-compare.py` reports rough centroid and low/mid/high band-energy timbre proxies in JSON/Markdown; synthetic tests cover high-frequency alternating, impulse, ramp, forward-loop boundary, ping-pong turnaround, interpolation diagnostics, and comparison optional-field behavior.
- Verification: synthetic Swift and Python tests cover the new diagnostics and microfixtures. Local private-module WAV/JSON/Markdown artifacts stayed under `/tmp` and out of git.
- Status: diagnostics/tooling only. This PR does not solve the remaining `xm-corpus-025` mismatch and does not claim a direct parity improvement. Recommended next implementation PR: C Mixer Cubic/FT2-Compatible Resampler Experiment if matching ft2-clone's configured interpolation target is desired; otherwise investigate replacement ramp shape or sample/instrument volume normalization as secondary alternatives.

### PR 2.7.11bk — ft2-clone Linear vs SINC8 Reference Comparison
- Scope: local-only diagnostics comparison for `xm-corpus-025` using VTX current default linear render, ft2-clone linear reference, and ft2-clone SINC8/default reference. No playback behavior changes, no C mixer DSP changes, no SINC8 or cubic implementation, no XM effect work, no runtime backend changes, no tracker viewport changes, and no parser changes.
- Findings: VTX linear is closer to ft2-clone linear than to ft2-clone SINC8/default, but only modestly. VTX-vs-ft2-linear correlation was about `0.927530` with gain-normalized RMS `0.038170`; VTX-vs-ft2-SINC8/default correlation was about `0.922506` with gain-normalized RMS `0.039823`. The ft2-clone linear and SINC8/default references differed with correlation about `0.998729`, raw RMS `0.005280`, gain-normalized RMS `0.005200`, and zero best local shift in top windows, so ft2-clone default is not equivalent to a linear renderer. The reference-mode delta is still far smaller than the remaining VTX mismatch.
- Change: public-safe docs record the anonymized comparison outcome and preserve generated WAV/JSON/Markdown reports as local `/tmp` artifacts only.
- Verification: `python3 -m unittest tools/audio_compare_tests.py`, `./scripts/check-files.sh`, `git diff --check`, and the repository privacy scan. Private/local modules, reference WAVs, generated WAVs, JSON, and Markdown reports stayed under `/tmp` or their existing local source locations and out of git.
- Status: diagnostics-only. Do not carry cubic experiment code from this evidence. Recommended next PR: focused resampler-window analysis or a separate SINC8 candidate experiment; keep linear renderer parity and sample/instrument volume normalization as follow-up alternatives if VTX remains far from ft2-clone linear in focused windows.

### PR 2.7.11bl — Sample / Instrument Volume Normalization Focused Parity
- Scope: diagnostics-first sample/instrument volume and per-voice gain investigation for `xm-corpus-025` against the confirmed ft2-clone linear reference profile. No gain behavior, C mixer DSP, panning law, period/sample-step formula, row/tick timing, XM effect coverage, runtime backend default, tracker viewport, or parser architecture changes.
- Findings: the current gain path is sample header volume `0...64` normalized once into `PlaybackSample.volume`, then note-trigger gain `sample_volume * (channel_volume / 64) * (global_volume / 64)`, with the C mixer applying `event_gain * volume_envelope * fadeout` before panning. The primary ft2-clone linear profile was 48 kHz 32-bit float, 10x amplification, master volume 256, Linear interpolation, Linear frequency slides, volume ramping enabled, precise BPM disabled, and no individual track rendering. Local `xm-corpus-025` VTX-vs-ft2-linear metrics remained correlation about `0.927530`, raw RMS difference about `0.101857`, gain-normalized RMS about `0.038170`, and VTX RMS about `0.189161` versus ft2-clone RMS about `0.102128`.
- Window evidence: the top windows around `75.5...75.6s`, `67.8...67.9s`, `79.3...79.4s`, and the remaining latest worst windows need local scalars around `0.462...0.489` versus a whole-song scalar about `0.500771`. Same-channel replacement completion frames are folded into the active-voice estimate, leaving the top windows at roughly 3-8 active voices. Global volume stays 64, envelope-enabled events are absent in those windows, and the dominant full-volume instrument/sample group accounts for most level-weighted contribution estimates. This does not prove a double-normalization, instrument default-volume, channel/global-volume, envelope/fadeout, or many-simultaneous-voice gain bug.
- Change: bounded render diagnostics now include sample volume, raw sample-volume estimate, normalized channel/global multipliers, and structured gain-construction metadata; the audio-correlation report now summarizes sample/instrument gain evidence, local scalar needs, active voice counts, final-gain histograms, and dominant instrument/sample contribution estimates while tolerating older diagnostics without those fields.
- Verification: synthetic bounded-render and audio-correlation tests cover the new diagnostics and missing-field behavior; local private-module WAV/JSON/Markdown artifacts stayed under `/tmp` and out of git.
- Status: diagnostics/tooling only. Recommended next PR: Loop-Crossing Timbre Microfixture or Replacement Ramp Shape / Timbre Parity focused on the dominant full-volume looped instrument/sample behavior, not a broad gain-policy change.

### PR 2.7.11bm — Loop-Crossing Timbre Microfixture / ft2-clone Linear Parity
- Scope: microfixture-first, diagnostics-first investigation of whether the remaining `xm-corpus-025` VTX-vs-ft2-clone Linear mismatch is caused by loop-crossing timbre behavior in long-lived full-volume looped samples. No XM effects, SINC8/cubic interpolation, panning law, period/sample-step formula, row/tick timing, runtime backend default, tracker viewport, parser architecture, gain policy, or broad C mixer DSP changes.
- Findings: synthetic C mixer microfixtures confirm forward-loop behavior for discontinuous boundaries, smooth boundaries, fractional overshoot, integer wraps, high-frequency looped samples, transient looped samples, and split-render determinism. Local `xm-corpus-025` comparison against the confirmed ft2-clone Linear profile remained correlation about `0.927530`, raw RMS difference about `0.101857`, gain-normalized RMS about `0.038170`, and whole-song scalar about `0.500771`. The top 12 windows still need local scalars around `0.462...0.489` and are dominated by the same looped instrument/sample group, but every top window reports zero estimated loop-boundary crossings.
- Change: the audio-correlation report now adds loop-crossing timbre evidence with active looped voices, loop start/end/length, sample-step/final-gain ranges, estimated crossing counts, source-position examples, residual timbre proxies, and dominant looped instrument/sample contribution estimates while tolerating older diagnostics without optional fields.
- Verification: synthetic audio-correlation tests cover loop-crossing summary output and missing optional fields; synthetic bounded-render tests cover the loop microfixtures. Local private-module WAV/JSON/Markdown artifacts stayed under `/tmp` and out of git.
- Status: diagnostics/tooling only. Recommended next PR: Replacement Ramp Shape / Timbre Parity, with sample/instrument volume edge cases kept separate unless new expected-value evidence appears.

### PR 2.7.11bn — Steady-State Looped Sample Timbre / Sample-Instrument Contribution Parity
- Scope: diagnostics-first investigation of the remaining `xm-corpus-025` VTX-vs-ft2-clone Linear mismatch in top windows dominated by the same looped instrument/sample group. No playback behavior, XM effects, SINC8/cubic interpolation, panning law, period/sample-step formula, row/tick timing, runtime backend default, tracker viewport, parser architecture, replacement-ramp behavior, or broad C mixer DSP changes.
- Findings: the primary ft2-clone Linear profile remains 48 kHz 32-bit float export, 10x amplification, master volume 256, Linear interpolation, Linear frequency slides, volume ramping enabled, precise BPM disabled, and no individual tracks/stems. The latest local comparison remained correlation about `0.927530`, raw RMS difference about `0.116031` for this explicit-level render, gain-normalized RMS about `0.038170`, and whole-song scalar about `0.463666`. The dominant group is instrument/sample `23/0`, sample length `53744`, forward loop `4056...53744` length `49688`, sample volume `64/64`, relative note `0`, finetune `16`, typical sample steps around `0.185927...0.278576`, and top-window contribution ratios about `92...100%`.
- Window evidence: top windows around `75.5...75.6s`, `67.8...67.9s`, `79.3...79.4s`, and `90.8...90.9s` have 3-5 active voices, zero loop-boundary crossings for the dominant group, zero sample-step updates, zero replacement ramps, final gains up to `1.0`, and source-position ranges before the loop start. Later top windows sometimes include strict loop-interior voices or replacement ramps, but those are not required to reproduce the highest-ranked residuals.
- Change: the correlation report now adds steady-state loop/sample contribution evidence with dominant looped group summaries, loop phase histograms, strict loop-interior classification, source-position ranges, residual timbre proxies, update/ramp counts, and missing-field tolerance. The focused-window timeline now reports per-voice contribution, loop phase, strict steady-state classification, sample-step/gain/ramp counts, dominant sample groups, and separates non-loop source-end crossings from loop-boundary crossings.
- Verification: synthetic audio-correlation tests cover the steady-state contribution summary and missing optional fields; focused-window tests cover the new timeline fields; bounded C mixer microfixtures cover steady forward-loop interior, repeated interior region energy, high/low-frequency loop proxies, full/half volume energy, and split-render determinism. Local private-module WAV/JSON/Markdown artifacts stayed under `/tmp` and out of git.
- Status: diagnostics/tooling only. Recommended next PR: Dominant Sample PCM / Resampler Pre-Loop Timbre Microfixture, with replacement-ramp shape kept secondary and only targeted if a ramp-dominated window is isolated.

### PR 2.7.11bo — ft2-clone Stem / VTX Isolated Channel Parity
- Scope: diagnostics-first comparison of ft2-clone individual-track references for `xm-corpus-025` against VTX solo-channel, solo-instrument, and solo-sample bounded renders. No new XM effects, SINC8/cubic interpolation, panning law changes, period/sample-step changes, row/tick timing changes, runtime backend changes, tracker viewport changes, parser refactors, or broad C mixer DSP rewrites.
- Findings: the ft2-clone stem pass used the confirmed Linear profile with individual-track rendering enabled. The focused worst windows around `75.5...75.6s`, `67.8...67.9s`, `79.3...79.4s`, `70.4...70.5s`, `89.9...90.0s`, and `92.2...92.3s` are dominated by instrument/sample `23/0` on one-based tracker channels 5, 6, and 7. Those VTX solo channels are timing-aligned and highly correlated after local scalar normalization, but they are globally much louder than the matching stems, with focused-window scalars near `0.221` for the dominant channels. Channel 8 is silent in both ft2-clone and VTX after the diagnostic windowed-isolation carryover fix.
- Classification: this pass showed the remaining mismatch was not full-mix accumulation-only, and the follow-up PCM/contribution audits ruled out a dominant-sample PCM decode/scaling or VTX voice-lifetime explanation for the focused windows. Timing, panning/stereo placement, loop-boundary crossing, sample-step updates, replacement ramps, and SINC8/default reference mode remain weakened as primary causes for those windows.
- Change: `vtx_render_bounded_xm` now accepts local diagnostic `--solo-channel`, `--solo-instrument`, and `--solo-sample` filters. Diagnostics JSON reports the isolation policy and included/muted scheduled-event counts. Windowed isolation now suppresses nonmatching continuation carryover, covered by a synthetic regression test.
- Verification: synthetic bounded-render tests cover solo-channel/solo-instrument/solo-sample filters, diagnostics JSON, argument validation, and the windowed carryover regression. Local private-module WAV/JSON/Markdown artifacts stayed under `/tmp` and out of git.
- Status: diagnostics-first with normal playback unchanged. Superseded next-target wording: after the PCM and full-mix contribution audits, follow-up parity work should focus on ft2-clone/VTX individual-track versus full-mix contribution scaling, volume ramping, and final mix policy rather than sample PCM decode or VTX voice lifetime.

### PR 2.7.11bp — Full-Mix Contribution Analysis Without Stem Assumptions
- Scope: diagnostics-first contribution accounting for the remaining `xm-corpus-025` VTX-vs-ft2-clone Linear mismatch around dominant internal instrument/sample `23/0`. No playback behavior, XM effects, SINC8/cubic interpolation, panning law, period/sample-step formula, row/tick timing, runtime backend default, tracker viewport, parser architecture, or gain policy changes.
- Findings: ft2-clone exported sample WAV/raw sample data and VTX decoded PCM match for the dominant sample, including frame count, peak/RMS, waveform shape, forward loop `4056...53744`, sample volume `64/64`, relative note `0`, and finetune `16`. Focused full-mix windows around `75.5...75.6s`, `67.8...67.9s`, and `79.3...79.4s` have one audible dominant-sample voice on each of tracker channels 5, 6, and 7, no replacement ramps, no note-off/cut/retrigger history, disabled envelopes, pre-loop source positions, and no excess same-channel voices. The dominant sample accounts for about `93...98%` of the level-weighted full-mix contribution estimate in those windows.
- Stem evidence: at diagnostic gain `0.25`, VTX solo channels 5, 6, and 7 still need whole-channel candidate-to-reference scalars around `0.869`, `0.894`, and `0.879` against the corresponding ft2-clone individual-track references, meaning the diagnostic-gain renders are only about `1.0...1.2 dB` louder. Because the VTX renders used `--gain 0.25`, the equivalent no-gain VTX scalars are about `0.217`, `0.223`, and `0.220`, or about `13 dB` louder before diagnostic export gain. Later top windows include zero-gain carryover voices and occasional 32-frame replacement ramps, but those voices do not explain the requested-window dominant-channel loudness.
- Change: `scripts/correlate-audio-comparison.py` now accepts `--focus-sample I:S` and `--focus-channels N,N`, and reports per-window focused active/audible voice counts, per-channel contribution estimates, per-voice age, source row, source sample position, loop phase, gain, channel/global volume, replacement state, key state, and cut/off/retrigger history. The change is diagnostics-only.
- Verification: synthetic audio-correlation tests cover per-voice contribution summaries, dominant-sample contribution ratios, voice-age histograms, and missing optional diagnostics fields. Local private WAV/JSON/Markdown artifacts stayed under `/tmp` and out of git.
- Status: diagnostics-only. Recommended next parity PR: ft2-clone/VTX Individual-Track vs Full-Mix Contribution Scaling, Volume Ramping, and Final Mix Policy for the dominant channel group.

### PR 2.7.11bq — ft2-clone Mixer Scaling / Volume Ramping Policy Audit
- Scope: diagnostics-only audit of ft2-clone final mix scaling, individual-track export, volume ramping, sample scaling, and VTX current contribution/export behavior for `xm-corpus-025`. No playback behavior, gain behavior, C mixer DSP, panning law, period/sample-step formula, row/tick timing, runtime backend default, tracker viewport behavior, parser architecture, or XM effect coverage changes.
- Findings: targeted local ft2-clone inspection found the 32-bit float output path applies amplification/master volume as `(amplification * masterVolume) / (32 * 256)`, so the primary Linear profile's 10x amplification and master volume 256 produce a final `0.3125` output factor. Full render and individual-track render use the same mix/export scaling path, and individual-track export mutes non-target channels without per-track normalization or attenuation. The local ft2-clone stem sum reconstructs the full render with scalar `1.0`, correlation `1.0`, peak `0.506383`, RMS `0.102128`, and zero overrange samples.
- Comparison: VTX 48 kHz Float32 unity export preserves overrange values and reported peak `1.925131`, RMS `0.408609`, `206808` Float32 overrange samples, and zero PCM16 clipping count for the full local target. The whole-song VTX-to-ft2 scalar was about `0.231827`; dominant-channel solo-to-stem scalars at unity were about `0.217`, `0.223`, and `0.220`, and focused worst windows clustered around `0.220971`. That matches ft2-clone's `0.3125` output scale combined with its about-`0.707` centered panning contribution, and weakens stem attenuation, VTX solo isolation scaling, dominant-sample PCM decode/scaling, sample-volume normalization, and 8-bit divisor hypotheses.
- Ramping policy: ft2-clone uses linear per-sample volume ramping. Quick note-start/replacement/stop/reset ramps are about 5 ms at render rate, and ordinary volume/pan updates ramp over one tick. VTX currently uses fixed 32-frame linear replacement ramps and fixed 32-frame gain/pan update micro-ramps. Ramping remains a plausible residual/timbre factor after scalar normalization, but it does not explain the primary raw loudness scalar in the focused windows.
- Verification: local ft2-clone full/stem references and VTX Float32 full/solo renders were compared with generated WAV/JSON artifacts kept under `/tmp` and out of git. Public docs use anonymized corpus labels only.
- Status: diagnostics-only. Recommended next PR: VTX Final Mix Scale / Export Reference Policy. Do not implement the policy change in this audit branch.

### PR 2.7.11br — Note-Start Fade-In / Ordinary Gain-Pan Smoothing Diagnostics
- Scope: diagnostics-only classification of whether remaining `xm-corpus-025` FT2-profile residual windows line up with ft2-clone note-start quick fade-in or ordinary volume/panning smoothing. No playback behavior, gain behavior, C mixer DSP, panning law, period/sample-step formula, row/tick timing, runtime backend default, tracker viewport behavior, parser architecture, or XM effect coverage changes.
- Findings: current VTX starts new notes immediately with no fade-in, uses fixed 32-frame ramps for ordinary active-voice gain/pan updates and outgoing same-channel replacement voices, and keeps note-cut/retrigger/transport stop paths hard. Targeted ft2-clone inspection found linear quick fades of about 5 ms for note starts/replacements/stops/resets and one-tick linear smoothing for ordinary volume/panning changes.
- Window evidence: the FT2-profile full-song comparison remained about `0.927530` correlation with gain-normalized RMS about `0.038170`. The top 12 windows classified as note-start-active in 7, ordinary-gain-update-active in 7, pan-update-active in 0, replacement-ramp-active in 3, stop/cut-active in 0, and steady-state in 4. The top-ranked window is an ordinary `Axy` gain-update window without note-start or replacement-ramp overlap. Focused individual-track references for tracker channels 5-7 were used locally; channel 7 residual timing overlaps several full-mix top windows, while pan update evidence remains absent.
- Change: `scripts/correlate-audio-comparison.py` now reports a smoothing/note-start window classification table and high-level policy notes. Synthetic tooling tests cover note-start fade-in windows, ordinary gain/pan update windows, volume-column/update counts, and steady-state windows without private fixtures.
- Verification: synthetic audio-correlation tests cover the new diagnostics; local private full/stem WAVs and generated JSON/Markdown reports stayed under `/tmp` and out of git. Public docs use anonymized corpus labels only.
- Status: diagnostics-only. Recommended next PR: One-Tick Gain Update Smoothing Experiment; keep Note-Start Fade-In Parity as secondary and do not target pan smoothing unless new evidence appears.

### PR 2.7.11bs — Minimal 5xy Tone Portamento + Volume Slide
- Scope: implement only XM effect-column `5xy` through the shared bounded/offline and CoreAudio C mixer runtime adapter paths, reusing current `3xx` tone-portamento target/speed sample-step updates and `Axy` tick-level volume-slide gain updates. `500` remains a no-op/deferred volume-slide-memory case, and `Rxy`, `Xxy`, `Lxx`, Amiga frequency-table behavior, `E0x`, `Vxx`/`Wxx`, parser changes, tracker viewport changes, backend defaults, and retired AVAudio paths remain out of scope.
- Diagnostics: bounded JSON reports `tone_portamento_volume_slide_5xy_effects`, render-level `tone_portamento_volume_slide_5xy_*` counters, first coordinates, no-active/no-target/no-speed/no-op buckets, and scheduled sample-step/gain update counts. Runtime adapter plans tag `5xy` sample-step and gain updates with effect metadata.
- Verification: synthetic fixtures cover detection/counting, active-voice sample-step and gain updates, `500` no-op diagnostics, no-active-voice diagnostics, same-cell note target setup without retriggering, mixed-nibble volume-slide policy, runtime adapter metadata, split/windowed render determinism, and existing `3xx`/`Axy`/`6xy`/`Kxx` regressions. Local-only corpus smoke artifacts stay under `/tmp` and out of git.
- Status: done.

### PR 2.7.11bt — Minimal Rxy Multi Retrigger
- Scope: implement only XM effect-column `Rxy` through the shared bounded/offline and CoreAudio C mixer runtime adapter paths, reusing the existing retrigger scheduler for active voices. Same-cell note rows trigger once at tick 0 and schedule generated retriggers on later interval ticks. `R00` remains an effect-memory-deferred no-op, and `Xxy`, `Lxx`, Amiga frequency-table behavior, `E0x`, `Vxx`/`Wxx`, parser changes, tracker viewport changes, backend defaults, and retired AVAudio paths remain out of scope.
- Diagnostics: bounded JSON reports `retrigger_effects`, render-level `rxy_multi_retrigger_*` counters, first coordinates, no-active/no-op buckets, interval and volume mode nibbles, scheduled retrigger frames, and volume-change counts. Runtime adapter plans tag `Rxy` note triggers with `rxy_multi_retrigger` metadata.
- Verification: synthetic fixtures cover detection/counting, active-voice retrigger scheduling, `R00` no-op diagnostics, no-active-voice diagnostics, same-cell note behavior, common-XM volume mode mapping and clamping, runtime adapter metadata, split/windowed render determinism, existing `E9x`/`ECx`/`EDx`/`Axy`/`EAx`/`EBx`/`5xy`/`Kxx` regressions, and local-only corpus smoke artifacts under `/tmp`.
- Status: done.

### PR 2.7.11bu — Expanded Corpus Residual Effect Memory / Volume Column Scan
- Scope: diagnostics-only static scan of the 36-module private mapped XM corpus after `Rxy`, focused on residual `Xxy`, `Lxx`, `3xx`/`Axy` memory, `7xy` tremolo, volume-column vibrato/tone-portamento, supported `Kxx`/`5xy`/`Rxy` residuals, high-byte classifications, and Amiga frequency-table pitch buckets. No playback behavior, parser behavior, tracker UI behavior, runtime backend selection, C mixer DSP behavior, or retired audio backends changed.
- Findings: the local scan covered 35 linear-table modules and 1 Amiga-table module. Linear-table residuals include 166 `Xxy` rows, 25 `Lxx` rows with envelope evidence on most active channels, 6,183 `300` rows with 6,153 memory reuses and 2 missing-memory cases, and 8,533 `A00` rows with 8,520 likely memory reuses if implemented. No `7xy`, `E7x`, volume-column vibrato-speed/depth, or Amiga-table `Xxy` rows were observed. Volume-column tone portamento appears only 5 times in one linear-table target. `Kxx` and `5xy` are fully applied in this static pass; `Rxy` residuals are applied, zero-interval no-op, or out-of-row classifications. `Vxx`/`Wxx` remain classification-only, and Amiga `2xx`/`3xx` stay in a separate frequency-table foundation bucket.
- Verification: generated Markdown/JSON reports stayed under `/tmp` with anonymized labels only. Follow-up implementation PR: `Axy` volume-slide memory.

### PR 2.7.11bv — Axy Volume-Slide Memory Foundation
- Scope: implement only per-channel Axy-style volume-slide memory in the shared Swift adapter path used by bounded offline C mixer renders and the CoreAudio C mixer runtime event plan. Nonzero `Axy` stores memory, `A00` replays it on post-tick gain updates, missing memory remains no-op/deferred, and `500` reuses the same shared memory path where already-supported `5xy` gain updates naturally share it. `Xxy`, `Lxx`, Amiga frequency-table behavior, `E0x`, `Vxx`/`Wxx`, `7xy`, volume-column tone portamento, parser changes, tracker viewport changes, backend defaults, C mixer DSP changes, and retired AVAudio backends remain out of scope.
- Diagnostics: bounded JSON reports `A00` detected/applied/no-op counts, `axy_volume_slide_memory_reused_count`, `axy_volume_slide_memory_missing_count`, memory source coordinates, memory direction/amount, scheduled gain-update counts, and `500` memory reuse/missing counts. Runtime adapter event categories tag memory-reused `A00` and `500` gain updates with `effect_memory_reused`.
- Verification: synthetic fixtures cover memory storage/replay, missing-memory no-op, per-channel isolation, active-voice tick updates, same-cell note plus `A00`, mixed-nibble policy preservation, `500` reuse through the shared path, runtime metadata, and split/windowed render determinism. Local-only corpus smoke artifacts stay under `/tmp` and out of git. Recommended next residual effect target: a separate `Xxy` extra-fine portamento investigation/foundation PR.

### PR 2.7.12 — Reference Comparison Stabilization Against MikMod/OpenMPT
- Scope: use local comparison findings to close targeted audible gaps after bounded candidate WAV export and enough mixer behavior exist
- Verification: documented local comparison reports kept out of the repository

### PR 2.7.13 — Remaining FT2/effect quirks after deterministic rendering exists
- Scope: target remaining XM/FT2 effect and compatibility gaps once deterministic rendering is available
- Verification: issue-based regression tests and local reference comparison

## Milestone 3: UI / Tracker Feel (Read-Only to Editing)

### PR 3.1 — Metadata panel + file open (done baseline)
- Scope: `File > Open…` + parsed metadata display + error alerts
- Verification: app build/test + manual open of `.mod`/`.xm`

### PR 3.2 — Pattern grid display (read-only)
- Scope: tracker grid widget/view, row/channel display, cursor visualization
- Verification: snapshot/golden rendering checks where feasible + manual keyboard navigation check

### PR 3.3 — Grid keyboard navigation parity
- Scope: row/channel/item cursor movement, paging, tab behavior
- Verification: UI-level tests if feasible, otherwise integration tests for cursor state transitions

### PR 3.4 — Note entry + row advance (edit disabled save)
- Scope: keyboard note mapping, edit cursor behavior, in-memory edits only
- Verification: deterministic editor-state tests + manual note entry feel validation

### PR 3.5 — Pattern edit operations
- Scope: insert/delete row, copy/cut/paste track/pattern/block basics
- Verification: unit tests on pattern mutations + manual tracker workflow pass

### PR 3.6 — Program/order display + pattern switching
- Scope: song order list and pattern selection/navigation
- Verification: UI integration tests or state-machine tests + manual navigation checks

## Milestone 4: Nostalgia / Look & Feel Restoration

### PR 4.1 — Tracker visual theme baseline
- Scope: typography/colors/grid spacing/channel separators inspired by classic VoodooTracker/FastTracker-era feel
- Verification: manual visual review against legacy references + screenshot snapshots

### PR 4.2 — Keyboard workflow polish
- Scope: shortcut parity tuning, focus handling, repeat behavior, latency polish
- Verification: manual usability checklist + regression tests for key-state transitions

### PR 4.3 — Legacy behavior parity fixes
- Scope: targeted UX/parsing/playback discrepancies found during comparison with legacy behavior
- Verification: issue-based regression tests + manual side-by-side checks

## Milestone 5: Modern Enhancements (After Core Parity)

### PR 5.x — Quality-of-life features (incremental)
Examples:
- Safer file recovery / autosave
- Improved file browser/import UX
- Export helpers / stem renders
- Theme packs / accessibility options
- MIDI input and modern controller support

Verification expectation for each PR:
- Feature-specific tests (unit/integration/golden)
- Manual workflow validation
- No regressions in parser/audio/UI smoke suites

## Definition of “Ready to Expand” (Gate)

Before major new features beyond parity:
- MOD/XM read-only compatibility is stable
- Basic module playback works for a representative smoke corpus
- Grid navigation and editing feel fast and predictable
- CI covers parser + app build/test + core smoke tests consistently

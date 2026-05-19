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
- First audible XM playback currently uses `AVAudioPlayerNode` plus `AVAudioUnitVarispeed` as a safe first-pass backend for sample triggering, Play/Stop behavior, and tracker follow integration.
- This is not the final tracker-accurate mixer architecture; current playback is first-pass XM-compatible rather than FT2-period-accurate or MikMod/OpenMPT accurate.
- Timing, pitch, panning/stereo placement, sample loops including ping-pong loops, instrument volume envelopes/fadeout, volume-column behavior, debug seeking, and playback trace export have all had compatibility passes.
- ADR 004 accepted the transition toward a deterministic pull-based software mixer, and the initial software mixer path now exists behind the playback/audio boundary. It renders silence, synthetic one-shot sample voices, synthetic forward/ping-pong loops, simple deterministic linear interpolation for fractional C-backed sample steps, volume/panning envelope foundations, frame-scheduled synthetic voices, synthetic row/tick scheduled voices, minimal synthetic patterns, and tiny bounded `PlaybackSong` adapter segments with parsed instrument sample-map/keymap selection, parsed volume-envelope point mapping plus first-pass sustain/loop/key-off/fadeout semantics, explicit XM linear-frequency pitch/period sample-step mapping where supported, conservative adapter-level volume-column set-volume/set-panning plus row-level volume/panning slide mapping, bounded/offline active-voice gain/pan updates for empty-note volume-column set-volume/set-panning cells, `Cxx` set volume, `8xx` set panning, nonzero row-level `Axy` volume slides, minimal `1xx`/`2xx` portamento up/down, minimal `3xx` tone portamento, and minimal row-level `Hxy` global volume slides with a fixed 32-frame gain/pan micro-ramp for changed active-voice updates, minimal `Fxx` speed/BPM timing changes, minimal nonzero `9xx` sample offset support, minimal `E9x` retrigger support, minimal `ECx` note cut and `EDx` note delay support, a fixed 256-voice scheduled/active C mixer pool for bounded offline renders, event-coverage diagnostics for missing-note investigation, and pattern traversal/timing hazard diagnostics for `Bxx`, `Dxx`, `EEx`, contextual `Fxx`, and other observed `E` subcommands offline only. It is not used for runtime playback.
- Local-only bounded candidate/reference comparison reports now have a committed blank findings template and workflow guidance for private local XM modules, plus a developer-only `vtx_render_bounded_xm` helper for producing bounded candidate WAVs and optional adapter diagnostics JSON through the existing offline export path. A local correlation script can map worst comparison windows to approximate bounded adapter rows/events, including pitch step/period/frequency, sample-selection method and fallback diagnostics, sample-offset diagnostics, minimal `1xx`/`2xx`/`3xx`/`E9x`/`ECx`/`EDx` diagnostics, volume/panning/global-volume state updates, event-coverage totals, skipped-note reasons, C mixer scheduled/active capacity values, rejected event coordinates, and traversal/timing hazards, and can summarize applied, ignored/no-op, deferred/unsupported, and unknown effect-column, volume-column, and state-update command frequency for follow-up diagnosis. Filled reports and generated artifacts remain outside git.
- Bounded diagnostics and the local correlation report now include applied `1xx`/`2xx` portamento-slide diagnostics, applied `3xx` tone-portamento diagnostics, deferred pitch-modulation counts, source coordinates, and a conservative pitch-effect recommendation for remaining `0xy` arpeggio, `5xy` portamento-family commands, `4xy`/`6xy` and volume-column vibrato commands, `7xy` tremolo, and volume-column tone portamento. Broader pitch-modulation effects remain separate implementation work.
- The developer-only bounded XM render helper keeps its conservative 60-second default clamp while allowing explicit longer local candidate renders through documented `--seconds` / `--max-frames` controls gated by `--allow-long-render`. It also has an opt-in `--until-song-end` mode with optional `--tail-seconds N` that computes the bounded selected order-range end from the adapter timing model, including minimal supported `Fxx` timing changes, without adding default looping or full FT2/OpenMPT song-duration parity.
- Long developer-only candidate WAV exports can opt into `--window-rows` row-windowed offline scheduling so the fixed C scheduled-voice pool is reused across deterministic render windows. Diagnostics aggregate per-window scheduled, accepted, rejected, carried, continuation, and boundary-drop counts. Windowed renders now carry practical active voice state across fresh C mixer windows where the bounded adapter can determine it, including source sample position, forward/ping-pong loop state, envelope position, key-off/release, fadeout, gain, pan, active gain/pan ramp state, and active `1xx`/`2xx`/`3xx` sample-step state, plus supported in-window gain/pan and sample-step updates for carried voices. Unsupported/deferred effects and full tracker voice semantics remain separate targeted work.
- Developer-only candidate WAV exports now report pre-export Float32 peak/RMS/overrange counts, post-gain peak/RMS, and PCM16 clipping/clamping counts. Optional `--gain` and `--headroom-db` apply only at the export boundary before PCM16 conversion; default output gain remains unchanged when neither option is passed.
- Local/offline click/discontinuity diagnostics can now analyze a rendered WAV for large adjacent-sample jumps and optionally correlate top jumps with bounded adapter diagnostics such as gain/pan updates, retriggers, note cuts/delays, looped voices, carried voices, and window boundaries. Gain/pan update events in the bounded/offline C mixer path now use the fixed 32-frame micro-ramp, while the analyzer remains diagnostic-only and does not change playback or render behavior.
- See `docs/decisions/002-first-pass-audio-backend.md` for the accepted backend decision and intended future path.
- See `docs/decisions/003-first-pass-playback-accuracy.md` for the current playback accuracy model and known approximations.
- See `docs/decisions/004-software-mixer-transition.md` for the current mixer transition plan.
- See `docs/decisions/005-software-mixer-core-language-boundary.md` for the architecture checkpoint that clarifies the final hot-path mixer boundary before more complex envelope, timing, and effect work.

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

The current runtime playback remains `AVAudioPlayerNode`-based. The software
mixer work should continue in small PRs and prove itself through offline renders
and reference comparison before any runtime backend switch.

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
- Scope: update bounded/offline channel volume and pan state for empty-note volume-column set-volume/set-panning cells, regular effect-column `Cxx` set volume, regular effect-column `8xx` set panning, and nonzero row-level `Axy` volume slides, with deterministic active-voice gain/pan update events where a carried voice exists. Leave `Hxy` global volume slide for the later targeted PR 2.7.10af.
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
- Scope: smooth already-supported bounded/offline active-voice gain and pan update events with a fixed 32-frame deterministic C mixer micro-ramp, including empty-note volume-column set-volume/set-panning, `Cxx`, `8xx`, and nonzero row-level `Axy`, while keeping `ECx` hard cuts immediate.
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
- Scope: apply only minimal XM `3xx` tone portamento in bounded/offline `PlaybackSong`-to-C-mixer renders by retaining the active voice, setting a linear-frequency target from normal-note `3xx` cells without retriggering the sample, and scheduling deterministic sample-step updates toward the target. Diagnose no-active/no-target/no-speed and keep `1xx`, `2xx`, `5xy`, and volume-column tone portamento deferred.
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

### PR 2.7.11 — Feature-Flagged Runtime Backend Switch
- Scope: add an opt-in runtime mixer backend while keeping the `AVAudioPlayerNode` backend available
- Verification: app playback smoke tests, backend selection tests, and fallback validation

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

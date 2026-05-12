# Audio Reference Comparison

VoodooTracker X can play XM files, but it does not yet provide meaningful direct
offline WAV export. This workflow compares a reference renderer WAV with a
VoodooTracker X WAV capture or future offline render when one is available.

Do not commit copyrighted modules or generated renders from them. Keep local
modules and WAVs in `/tmp`, `~/Desktop`, or another untracked location.

## Reference WAV

Prefer `openmpt123`/libopenmpt when installed:

```bash
openmpt123 --render /tmp/darkl-openmpt.wav /Users/syncomm/Desktop/_DARKL.XM
```

MikMod is also acceptable. Use its WAV disk writer:

```bash
mikmod -q -d 2,file=/tmp/darkl-mikmod.wav -f 44100 -o 16s /Users/syncomm/Desktop/_DARKL.XM
```

Renderer defaults differ. Record renderer name/version, sample rate,
interpolation, loop, and fade settings in bug reports or PR notes. Some modules
can render for a long time depending on song length and loop behavior, so keep
renders in `/tmp` and stop the renderer manually if needed.

## VoodooTracker X WAV

Until direct export exists, capture app output manually with a local macOS audio
capture setup and save it as PCM WAV outside the repository, for example:

```text
/tmp/darkl-voodootrackerx.wav
```

When direct export is added, use the exported file as the candidate WAV.

## Planned Software Mixer Validation

The target software mixer architecture is documented in
`docs/decisions/004-software-mixer-transition.md`. The initial software mixer
skeleton and offline render harness now exist behind the playback/audio boundary.
The harness renders bounded deterministic Float32 PCM blocks for tests and
future export tooling. It can render explicitly supplied synthetic one-shot
sample voices plus deterministic synthetic forward and ping-pong loops, but it
still does not render XM instruments, patterns, song timing, envelopes, effects,
or reference WAV exports. Loop support is currently limited to the synthetic
offline mixer path; parser integration, module-derived loop metadata, envelopes,
effects, timing, and reference WAV comparison remain future work. Requests above
the configured frame maximum are clamped rather than allowed to render
unbounded PCM.

Runtime playback still uses `AVAudioPlayerNode` / `AVAudioUnitVarispeed`; the
offline harness is not part of live playback and should not change audible
behavior. WAV/reference comparison against real modules becomes meaningful only
after the software mixer is connected to module-derived sample, timing, loop,
envelope, panning, and effect decisions. Generated WAV files, playback traces,
comparison reports, and local modules must remain outside the repository.
`/Users/syncomm/Desktop/_DARKL.XM` is a local-only manual regression module and
must not be committed or copied into fixtures.

Once module-connected sample rendering exists, prefer the offline harness over
manual app capture for mixer validation:

- render the first N seconds of the local test module to a candidate WAV
- render the same segment with `openmpt123` or MikMod using recorded settings
- compare both WAV files with `scripts/audio-compare.py`
- capture a playback trace for the same segment when audio metrics point to a
  timing, loop, envelope, panning, or effect-state mismatch
- keep the local module, WAVs, traces, and reports outside the repository

Runtime playback should not switch to the software mixer until this offline
workflow can produce useful, reproducible comparison reports.

## Compare WAV Files

```bash
./scripts/audio-compare.py \
  --reference /tmp/darkl-openmpt.wav \
  --candidate /tmp/darkl-voodootrackerx.wav \
  --seconds 30 \
  --report /tmp/darkl-audio-compare.txt
```

Omit `--report` to print to stdout. The report includes WAV format, duration
difference, sample rate/channel/sample-width mismatches, RMS and peak levels,
RMS and peak differences, rough normalized correlation, and first-difference
timestamp when sample rate and channel count match.

## Limitations

This is a developer diagnostic tool, not a conformance test.

- Supports uncompressed PCM WAV only.
- Does not resample, downmix, upmix, time-align, or compensate for renderer
  latency.
- Correlation is computed over interleaved PCM samples and is intentionally
  rough.
- Manual app captures can include device latency, start offset, gain changes, or
  system audio processing.

Use the report to identify large differences and guide follow-up debugging
before adding more playback effects.

For playback decision diagnostics, capture a VoodooTracker X JSONL trace with
`docs/playback-trace.md` and compare the trace's order, row, tick, channel,
effect, volume, and pitch/rate decisions against the audio report.

## Manual Verification

- Render a short reference WAV with `openmpt123` or MikMod.
- Capture or export a comparable VoodooTracker X WAV if available.
- Run `./scripts/audio-compare.py` with `--seconds 30`.
- Confirm the report shows duration, format, RMS, peak, and mismatch details.
- Confirm sample comparison is skipped clearly when formats do not match.
- Confirm no playback behavior changed.
- Confirm tracker viewport behavior was not modified.

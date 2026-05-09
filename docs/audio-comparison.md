# Audio Reference Comparison

VoodooTracker X can play XM files, but it does not yet provide direct offline
WAV export. This workflow compares a reference renderer WAV with a
VoodooTracker X WAV capture when one is available.

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

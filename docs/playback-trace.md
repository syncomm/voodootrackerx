# Playback Trace Export

VoodooTracker X can export a developer-only playback trace as JSON Lines
(`.jsonl`). The trace records playback decisions without changing playback
behavior. Use it when comparing VoodooTracker X against MikMod, OpenMPT, or
other reference playback for real XM files.

Do not commit traces from copyrighted modules. Keep local modules and generated
trace files in `/tmp`, `~/Desktop`, or another untracked location.

## Enable Trace Export

Trace export is disabled by default. In Debug builds, set
`VTX_PLAYBACK_TRACE_PATH` to the local JSONL file path before launching the app:

```bash
VTX_PLAYBACK_TRACE_PATH=/tmp/darkl-vtx-playback.jsonl \
./build/Build/Products/Debug/VoodooTrackerX.app/Contents/MacOS/VoodooTrackerX
```

For the local `_DARKL.XM` diagnostic target:

```bash
xcodebuild \
  -project app/VoodooTrackerX/VoodooTrackerX.xcodeproj \
  -scheme VoodooTrackerX \
  -configuration Debug \
  -derivedDataPath build \
  build

VTX_PLAYBACK_TRACE_PATH=/tmp/darkl-vtx-playback.jsonl \
VTX_OPEN_PATH=/Users/syncomm/Desktop/_DARKL.XM \
./build/Build/Products/Debug/VoodooTrackerX.app/Contents/MacOS/VoodooTrackerX
```

Press Play, let playback run for 10-30 seconds, then press Stop. The trace file
is flushed on stop.

## Trace Fields

Each line is one JSON object. The schema is intentionally flat so it can be
filtered with `jq`, diffed, or imported into a spreadsheet.

Example:

```json
{"channelIndex":0,"computedPanning":-0.4980392,"computedPeriodApproximation":5.273184,"computedPitchSemitones":0,"computedRate":0.189639,"computedVolume":1,"decision":"triggered","decisionReason":"row_note","effect":"0902","effectCommand":"09","effectParameter":"02","instrumentIndex":1,"noteValue":49,"orderIndex":0,"patternIndex":2,"rowIndex":0,"sampleIndex":0,"sampleOffset":512,"schemaVersion":1,"tickIndex":0,"tickInRow":0}
```

Recorded fields include:

- `tickIndex`, `orderIndex`, `patternIndex`, `rowIndex`, `tickInRow`
- `channelIndex`
- `noteValue`, `instrumentIndex`, `sampleIndex`
- `effectCommand`, `effectParameter`, `effect`
- `computedVolume`
- `computedPanning` (current AVAudio pan value in the `-1...1` range when known)
- `computedPitchSemitones`, `computedRate`, `computedPeriodApproximation`
- `sampleOffset`
- `decision`: `triggered`, `delayed`, `cut`, `retriggered`, `ignored`, or `updated`
- `decisionReason`: short machine-readable context for the decision

## Inspecting A Trace

Show the first few trigger decisions:

```bash
jq 'select(.decision == "triggered") | {tickIndex, orderIndex, rowIndex, channelIndex, noteValue, instrumentIndex, effect, computedVolume, computedPanning, computedRate, sampleOffset}' \
  /tmp/darkl-vtx-playback.jsonl | head -80
```

Find delayed notes, cuts, and retriggers:

```bash
jq 'select(.decision == "delayed" or .decision == "cut" or .decision == "retriggered")' \
  /tmp/darkl-vtx-playback.jsonl
```

Compare with an audio report from `docs/audio-comparison.md` by matching the
approximate timestamp from the report to `tickIndex`, `orderIndex`, and
`rowIndex` in the trace.

## Limitations

- Trace export is an observability tool only; it does not make playback more
  compatible.
- The current backend uses `AVAudioPlayerNode` and `AVAudioUnitVarispeed`, so
  pitch and period fields are approximations of current scheduling decisions,
  not FastTracker II period math.
- Panning is first-pass only: XM `0...255` channel state maps to the current
  AVAudio `-1...1` pan control, not a tracker-accurate custom mixer.
- The trace records current effect handling. Unsupported XM effects are still
  unsupported.
- Trace files can grow quickly because row decisions and tick updates are
  recorded per channel.

## Manual Verification

- Launch the Debug app with `VTX_PLAYBACK_TRACE_PATH` set.
- Load `/Users/syncomm/Desktop/_DARKL.XM` or another local XM file.
- Press Play for 10-30 seconds.
- Press Stop.
- Confirm the JSONL file exists and contains order, pattern, row, tick,
  channel, note, instrument, effect, volume, panning, pitch/rate, sample offset,
  and decision fields.
- Launch without `VTX_PLAYBACK_TRACE_PATH` and confirm normal playback still
  works.
- Confirm tracker viewport behavior was not modified or regressed.

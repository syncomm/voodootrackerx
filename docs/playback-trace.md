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
{"audioBufferSampleRate":44100,"bpm":183,"channelIndex":0,"computedFrequency":8363,"computedPanning":-0.4980392,"computedPeriodApproximation":5.273184,"computedPitchSemitones":0,"computedRate":0.189639,"computedVarispeedRate":1,"computedVolume":1,"decision":"triggered","decisionReason":"row_note","effect":"0902","effectCommand":"09","effectParameter":"02","finetune":0,"instrumentIndex":1,"loopEnabled":false,"loopEndFrame":0,"loopLength":0,"loopLengthFrames":0,"loopStart":0,"loopStartFrame":0,"loopType":0,"loopTypeName":"none","noteValue":49,"orderIndex":0,"patternIndex":2,"rateBasis":"targetFrequency/audioBufferSampleRate","relativeNote":0,"rowDuration":0.0273224,"rowIndex":0,"sampleIndex":0,"sampleLength":1024,"sampleOffset":512,"schemaVersion":1,"sourceSampleRate":8363,"speed":2,"targetFrequency":8363,"tickDuration":0.0136612,"tickIndex":0,"tickInRow":0,"usesLinearFrequencyTable":true}
```

Recorded fields include:

- `tickIndex`, `orderIndex`, `patternIndex`, `rowIndex`, `tickInRow`
- `speed`, `bpm`, `tickDuration`, `rowDuration`
- `channelIndex`
- `usesLinearFrequencyTable`
- `noteValue`, `instrumentIndex`, `sampleIndex`, `relativeNote`, `finetune`
- `effectCommand`, `effectParameter`, `effect`
- `computedVolume`, `finalAppliedVolume`
- `computedPanning` (current AVAudio pan value in the `-1...1` range when known)
- `envelopeEnabled`, `envelopeTick`, `envelopeValue`,
  `envelopeSustainActive`, `envelopeLoopActive`, `fadeoutValue`
- `sourceSampleRate`, `audioBufferSampleRate`, `targetFrequency`,
  `computedPitchSemitones`, `computedFrequency`, `computedVarispeedRate`,
  `computedRate`, `rateBasis`, `computedPeriodApproximation`
- `sampleOffset`, `sampleLength`, `loopStart`, `loopLength`, `loopType`,
  `loopTypeName`, `loopEnabled`, `loopStartFrame`, `loopEndFrame`,
  `loopLengthFrames`
- `decision`: `observed`, `triggered`, `delayed`, `cut`, `retriggered`,
  `ignored`, or `updated`
- `decisionReason`: short machine-readable context for the decision

The engine emits an `observed` event with
`decisionReason == "row_timing_before_effects"` before applying row-level timing
commands. This captures header timing such as `_DARKL.XM`'s `speed=2` and
`bpm=183` before a row `Fxx` command changes speed or BPM.

## Inspecting A Trace

Show the first few trigger decisions:

```bash
jq 'select(.decision == "triggered") | {tickIndex, orderIndex, rowIndex, channelIndex, speed, bpm, tickDuration, rowDuration, noteValue, instrumentIndex, relativeNote, finetune, sourceSampleRate, audioBufferSampleRate, targetFrequency, computedRate, rateBasis, computedVolume, envelopeEnabled, envelopeTick, envelopeValue, envelopeSustainActive, envelopeLoopActive, fadeoutValue, finalAppliedVolume, sampleOffset, sampleLength, loopEnabled, loopStartFrame, loopEndFrame, loopLengthFrames, loopType, loopTypeName}' \
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
  pitch and period fields are approximations of current scheduling decisions.
  Linear-frequency modules use note/relative-note/finetune frequency
  calculations, but the backend is still not a FastTracker II mixer.
- The current backend pre-renders scheduled sample buffers at
  `audioBufferSampleRate` and traces `computedRate` as
  `targetFrequency/audioBufferSampleRate`.
- Forward sample loops are supported by scheduling the pre-loop/first-loop
  region once and then scheduling the loop region with AVAudio's buffer loop
  option. Ping-pong loops are detected as `ping_pong_deferred` and remain a
  future custom-mixer/backend task.
- Panning is first-pass only: XM `0...255` channel state maps to the current
  AVAudio `-1...1` pan control, not a tracker-accurate custom mixer.
- Volume envelopes are first-pass playback state. Envelope points are linearly
  interpolated per tick, sustain and loop points use deterministic basic
  handling, and volume fadeout advances after XM key-off (`noteValue == 97`).
  Exact FastTracker II envelope quirks and sample-accurate timing remain future
  custom-mixer work.
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
  speed, BPM, tick and row duration, channel, note, instrument, effect, volume,
  panning, pitch/rate/frequency, rate basis, envelope/fadeout fields, sample
  offset, sample loop metadata, loop scheduling fields, and decision fields.
- Launch without `VTX_PLAYBACK_TRACE_PATH` and confirm normal playback still
  works.
- Confirm tracker viewport behavior was not modified or regressed.

# Audio Reference Comparison

This is the current local workflow for comparing VoodooTracker X candidate WAVs
against reference renders. It is diagnostic evidence only. It does not prove
tracker semantic correctness and should lead to one narrow follow-up PR at a
time.

Older investigation notes were moved to
`docs/reports/audio-comparison-history.md`. Do not make that history file
normal agent reading.

## Current Backend Context

- Runtime playback defaults to the CoreAudio DefaultOutput Audio Unit C mixer.
- `VTX_AUDIO_BACKEND=c_mixer` and `VTX_AUDIO_BACKEND=c_mixer_coreaudio` select
  the same CoreAudio C mixer host.
- `VTX_AUDIO_BACKEND=av_audio` is retired and falls back to the CoreAudio C
  mixer with a diagnostic fallback reason.
- Offline C mixer render/export is the authoritative comparison workflow.
- Runtime CoreAudio capture and offline render have been shown equivalent for
  tested modules when sample rate, gain/headroom, and bounds match.

Do not infer behavior changes from a comparison report alone. Use reports to
choose the smallest next implementation or diagnostic PR.

## Primary Reference Policy

For FT2-style linear XM comparisons, ft2-clone Linear is the preferred primary
reference when it can be exported locally with matching settings.

Record these reference settings in local notes or public-safe summaries:

- renderer name and version
- sample rate
- WAV format and bit depth
- Linear interpolation
- Linear frequency slides
- amplification and master volume
- volume ramping setting
- precise BPM setting
- whether individual-track/stem export was used

MikMod, OpenMPT/libopenmpt, Renoise, and other renderers are secondary
triangulation references. Their defaults can change duration, gain, ramping,
interpolation, and loop behavior, so do not mix reference families in one
conclusion unless the task is explicitly a settings experiment.

## Candidate Render Command

Write candidates and diagnostics outside the repository:

```bash
LOCAL_XM="path-to-untracked-local-module.xm"
ORDER_COUNT="module-song-length"

swift run vtx_render_bounded_xm \
  --input "$LOCAL_XM" \
  --output /tmp/vtx-ft2-profile-candidate.wav \
  --diagnostics-json /tmp/vtx-ft2-profile-diagnostics.json \
  --order 0 \
  --order-count "$ORDER_COUNT" \
  --sample-rate 48000 \
  --until-song-end \
  --tail-seconds 3 \
  --window-rows 64 \
  --allow-long-render \
  --wav-format float32 \
  --mix-profile ft2
```

Use the module's effective song length for `ORDER_COUNT` when rendering a full
one-pass local comparison. Keep the resolved private module path and generated
diagnostics under `/tmp` or another ignored local path.

For shorter bounded checks, constrain the render:

```bash
swift run vtx_render_bounded_xm \
  --input "$LOCAL_XM" \
  --output /tmp/vtx-bounded-candidate.wav \
  --diagnostics-json /tmp/vtx-bounded-diagnostics.json \
  --order 10 \
  --order-count 1 \
  --rows 16 \
  --sample-rate 48000 \
  --wav-format float32 \
  --mix-profile ft2
```

The helper uses the existing parser, playback builder, and bounded offline C
mixer render/export path. It must not be treated as a parser bypass or an
alternate runtime backend.

## Float32 vs PCM16

Use `--wav-format float32` when:

- comparing against ft2-clone 32-bit float exports
- measuring overrange values before choosing headroom
- avoiding an implicit PCM16 clamp decision
- generating evidence for gain, scaling, or mix-profile work

Use the default PCM16 export when:

- doing a quick listening smoke check
- testing a tool that only accepts PCM WAV
- intentionally checking clipping/clamping behavior

PCM16 clamps encoded samples after export gain/headroom. Float32 writes IEEE
float WAV format code `3` and preserves overrange samples as stored.

Export gain controls are export-boundary policy only:

- `--gain N` applies an explicit linear multiplier.
- `--headroom-db N` applies a dB attenuation.
- `--auto-headroom` computes local export gain from rendered Float32 peak with
  a fixed safety margin.

These options do not change C mixer DSP, runtime playback, parser behavior, or
tracker UI behavior.

## FT2 Mix Profile vs VTX Mix Profile

`vtx_render_bounded_xm` supports explicit mix profiles:

- `--mix-profile vtx` is the default project policy: current VTX panning and
  unity offline mix scale.
- `--mix-profile ft2` is the FT2-style reference policy used for ft2-clone
  Linear comparisons. It applies equal-power center panning and the ft2-clone
  Linear output scale inside the offline render block before WAV export gain.

Use `--mix-profile ft2` for FT2-style XM parity comparisons. Use
`--mix-profile vtx` when validating default VTX output behavior or checking
that a change did not alter the project profile.

Do not compare an FT2-profile candidate against a VTX-profile candidate without
labeling the report as a mix-profile experiment.

## Reference Renderers

When ft2-clone is used as the primary reference, export outside the repository
and record the full profile. Prefer Float32 for direct comparison with VTX
Float32 candidates.

When `openmpt123` is installed locally, a simple full render can be useful for
secondary checks:

```bash
openmpt123 --samplerate 48000 \
  --render /tmp/openmpt-reference.wav \
  "$LOCAL_XM"
```

MikMod is also acceptable for secondary checks, but avoid its default playlist
mode with the WAV disk writer. Use one-pass mode when available:

```bash
mikmod -norc -q --playmode 0 --noloops \
  -d 2,file=/tmp/mikmod-reference.wav \
  -f 48000 \
  -o 16s \
  "$LOCAL_XM"
```

If a renderer cannot bound by order/row, record manual trimming, duration
bounds, silence padding, or offset workarounds in the local report.

## Compare WAVs

Use the thin smoke wrapper when you want default report paths under `/tmp`:

```bash
python3 scripts/local-reference-compare-smoke.py \
  --candidate /tmp/vtx-ft2-profile-candidate.wav \
  --reference /tmp/ft2-linear-reference.wav \
  --label local-linear-ft2-profile-smoke \
  --metadata "48000 Hz Float32, FT2 mix profile, reference settings recorded locally"
```

Use `scripts/audio-compare.py` directly for explicit JSON/Markdown paths:

```bash
python3 scripts/audio-compare.py \
  --candidate /tmp/vtx-ft2-profile-candidate.wav \
  --reference /tmp/ft2-linear-reference.wav \
  --seconds 240 \
  --window-ms 100 \
  --top-windows 8 \
  --alignment-search-frames 256 \
  --json /tmp/vtx-audio-compare.json \
  --markdown /tmp/vtx-audio-compare.md
```

The comparison script supports uncompressed PCM WAV input and IEEE Float32 WAV
input. It does not resample, normalize, downmix, upmix, or compensate for
renderer latency. Match sample rate, channel count, duration, and bounds before
interpreting sample-level metrics.

## Correlate Worst Windows

When candidate diagnostics JSON is available, correlate comparison windows with
adapter/render events:

```bash
python3 scripts/correlate-audio-comparison.py \
  --comparison-json /tmp/vtx-audio-compare.json \
  --diagnostics-json /tmp/vtx-ft2-profile-diagnostics.json \
  --output-markdown /tmp/vtx-audio-correlation.md \
  --label local-linear-ft2-profile \
  --metadata "public-safe summary; private settings kept locally"
```

For known timestamps, use focused windows instead of relying only on top
ranked comparison windows:

```bash
python3 scripts/focused-window-voice-timeline.py \
  --diagnostics-json /tmp/vtx-ft2-profile-diagnostics.json \
  --window 75.5:75.7 \
  --markdown /tmp/vtx-focused-window.md
```

Use these reports to classify the likely mismatch family: timing, traversal,
pitch/sample-step, gain/headroom, panning/stereo, envelope/fadeout, loop,
sample offset, retrigger, note cut/delay, unsupported effect, or unknown.
Candidate diagnostics JSON includes `lxx_set_envelope_position_effects` for
first-pass effect-column `Lxx` volume-envelope-position updates, including
applied/no-active/no-envelope status and requested/applied envelope positions.
It also reports volume-column `F0...FF` tone portamento through
`tone_portamento_effects` with `command_source: "volume_column"`,
`raw_volume_column`, applied/no-active/no-target/no-speed status, and scheduled
sample-step update counts.

## Runtime Capture Checks

Use runtime capture only when investigating host/runtime delivery. It is not
the first tool for FT2 reference comparison.

If runtime/offline mismatch is suspected:

1. Capture runtime CoreAudio output locally with
   `VTX_C_MIXER_RUNTIME_CAPTURE_PATH`.
2. Render an offline C mixer candidate at the runtime trace sample rate.
3. Compare runtime capture vs offline render with `scripts/audio-compare.py`.
4. Correlate with runtime trace only if the WAV comparison shows a real
   mismatch after bounds and gain are checked.

Tested runtime CoreAudio captures have matched offline render behavior at the
render-core/output-capture level. Treat a new mismatch as a diagnostic lead,
not proof that playback semantics should change.

## Effect Coverage Summaries

For effect implementation work, read `docs/xm-effect-support.md` first. It is
the canonical support table.

Local coverage summaries can use:

```bash
python3 scripts/summarize-xm-effect-coverage.py \
  --diagnostics-json /tmp/vtx-ft2-profile-diagnostics.json \
  --markdown /tmp/vtx-effect-coverage.md
```

Keep generated reports local unless the maintainer explicitly requests a
public-safe committed report under `docs/reports/`.

## Interpreting Metrics

Useful `scripts/audio-compare.py` evidence includes:

- duration and frame-count deltas
- RMS and peak levels
- normalized RMS difference
- scalar gain-normalized RMS difference
- max absolute difference
- clipping or overrange counts
- stereo-as-is, mono, left, right, and side-channel comparisons
- normalized correlation
- worst mismatch windows
- optional local alignment search results

Lower numeric difference is not automatically more correct tracker behavior.
Check whether the candidate/reference settings match before choosing work.

## Report Placement

Use these locations:

- `/tmp` for local WAVs, JSON, Markdown, traces, screenshots, logs, and filled
  findings reports.
- `docs/templates/local-audio-comparison-findings.md` as the blank report
  template.
- `docs/reports/` only for public-safe long reports explicitly requested by
  the maintainer.
- `docs/reports/audio-comparison-history.md` for archived historical context.

Do not append long investigation reports to `docs/audio-comparison.md`,
`docs/roadmap.md`, `docs/dev-roadmap.md`, or `docs/playback-trace.md`.

## Private Artifact Rules

- Never commit private/local modules.
- Never commit generated WAVs, diagnostics JSON, comparison Markdown, traces,
  screenshots, logs, or listening notes.
- Never publish private filenames, local absolute paths, or machine-specific
  notes.
- Use anonymized labels only when examples are necessary.
- Keep local corpus label maps outside the repository.
- Before committing, run `git status --short` and stage only intended docs or
  source changes.

## Manual Verification For This Workflow

Before a comparison PR or report:

- confirm candidate/reference sample rate, channels, bounds, and profile
- inspect candidate export peak/overrange/clipping diagnostics
- run `scripts/audio-compare.py` on existing WAVs
- correlate worst windows when diagnostics JSON exists
- confirm generated artifacts are outside git
- confirm no playback, parser, tracker viewport, or runtime backend behavior
  changed unless that was the explicit PR scope

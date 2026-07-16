# Synthetic XM Reference Fixture Pack Plan

This plan governs the public-safe XM fixture pack for parser, editor,
instrument/sample, preview, and later audio-comparison tests. The completed
three-fixture instrument series adds deterministic fixture assets and generator/test tooling only;
it does not change backend, parser, writer, mixer, DSP, or editor behavior.

## Purpose

VoodooTracker X currently has tiny redistribution-safe parser fixtures under
`tests/fixtures/`, including `minimal.xm`. Those files are useful smoke inputs,
but they are intentionally too small to cover meaningful instrument/sample
payload, positive editor preview availability, loop behavior, envelopes, or
focused FT2-style comparison cases.

The future pack should provide small, reproducible XM modules that can live in
the repository and CI without depending on private modules, local absolute
paths, or generated local reports. Fixtures should isolate one behavior family
at a time instead of becoming one large all-effects module.

## Proposed Structure

Proposed layout:

```text
tests/reference-xm/
  README.md
  source/
  generated/
  reference-renders/
```

Directory intent:

- `README.md`: fixture provenance, license statement, generation commands, and
  expected test ownership.
- `source/`: hand-authored source descriptions or generator inputs that are
  readable in review.
- `generated/`: committed binary XM files, only after an explicit reviewed PR
  decides each file is small and redistributable.
- `reference-renders/`: optional committed reference WAVs or metrics, only
  after a future PR explicitly approves their size, license, and value.

Do not create empty directories unless the repo later adopts tracked
placeholders. Track reviewable files, such as source manifests and README
contracts, when they establish the structure.

Current skeleton:

- `tests/reference-xm/README.md` now documents the fixture-pack contract.
- `tests/reference-xm/source/basic-instrument-sample.manifest.json` is the
  deterministic source manifest for the approved generated fixtures.
- `scripts/generate-synthetic-xm-fixtures.py` prints or writes that manifest
  and can validate, generate one or all approved binary XM fixtures, or verify
  committed bytes without emitting reference renders.
- `tests/reference-xm/generated/basic-instrument-sample.xm` is the first
  committed generated fixture: one instrument, one 64-frame synthetic sample,
  and a tiny pattern for parser/editor positive-path tests.
- `tests/reference-xm/generated/multi-pattern-loop-boundary.xm` is a committed
  generated traversal fixture: three short patterns, three order positions,
  and row-0 note triggers for public-safe order-boundary adapter-plan tests.
- `tests/reference-xm/generated/instrument-sustained-defaults.xm` is a
  committed 16-bit sustained sine fixture with a forward loop, neutral sample
  metadata, and a simple volume envelope for Instrument/Sample Editor,
  audition, editable-copy, and Export XM/reopen checks.
- `tests/reference-xm/generated/instrument-metadata-matrix.xm` is a committed
  five-instrument pairwise matrix covering exact panning/volume/tuning values,
  8/16-bit PCM, no/forward/ping-pong loops, and distinct deterministic waveforms.
- `tests/reference-xm/generated/instrument-envelopes-keymap.xm` is a committed
  two-sample split-keymap fixture covering volume/panning envelopes, fadeout,
  autovibrato metadata, and exact editable-copy/Export XM preservation.

The manifest, generator, mathematical PCM, patterns, instrument metadata, and
generated XMs are original VoodooTracker X project assets and inherit the
repository's MIT license. They are not derived from private modules,
third-party songs, public XMs, or imported sample material.

Run the corpus workflow from the repository root:

```bash
python3 scripts/generate-synthetic-xm-fixtures.py --validate
python3 scripts/generate-synthetic-xm-fixtures.py --write-xm
python3 scripts/generate-synthetic-xm-fixtures.py --verify
```

`--fixture NAME.xm` scopes generation or verification to one fixture.
`--output-dir` confines test generation to a temporary pack root. The committed
sustained XM is 33,486 bytes with SHA-256
`babedfc9bd79f7e1ac79dbec6493e2182182700a8855c42cd15405f4eb6f0fde`;
the metadata matrix is 5,635 bytes with SHA-256
`590e4aaafc71c41130cb1a9a4e768220c38c6e8dcdd3529d9be6e35ec400aef3`;
the envelopes/keymap fixture is 6,870 bytes with SHA-256
`02c195c97ea64b0be56f75c86e4b2a5e565690cff39500f09dadc3441eeeee09`.

## Fixture Families

Start with focused fixtures that each prove one behavior class:

- `basic-instrument-sample.xm`: one instrument, one sample, simple note events,
  and real sample payload for parser/editor positive-path tests.
- `multi-pattern-loop-boundary.xm`: three short patterns and three order
  positions with simple row-0 notes, for adapter-plan traversal tests and
  future adapter-safe pattern-loop design work. It is not pattern-loop playback
  and contains no pattern-loop effect commands.
- `instrument-sustained-defaults.xm`: landed sustained 16-bit sine with a
  smooth forward loop and ordinary metadata for public editor/audition tests.
- `instrument-metadata-matrix.xm`: landed five-instrument pairwise sample-header
  matrix with waveforms, both bit depths, and all three XM loop modes.
- `instrument-envelopes-keymap.xm`: landed multi-sample map with volume/panning
  envelopes, fadeout, and autovibrato preservation.
- `note-entry-preview.xm`: tiny loaded-module payload for selected
  instrument/sample display and future preview availability tests.
- `looped-sample.xm`: forward loop metadata and a steady loop segment.
- `ping-pong-loop.xm`: ping-pong loop metadata and a waveform that makes the
  reversal easy to inspect.
- `volume-envelope.xm`: sustained sample with a simple volume envelope.
- `panning-envelope.xm`: deferred until panning-envelope editor and playback
  expectations are ready.
- `pitch-effects.xm`: focused pitch commands such as portamento and vibrato.
- `volume-effects.xm`: focused volume slides, tremolo, global volume, and
  related volume behavior.
- `traversal-effects.xm`: position jump, pattern break, pattern delay, and
  loop traversal cases.
- `retrigger-cut-delay.xm`: retrigger, note cut, note delay, and key-off cases.
- `effect-memory.xm`: small effect-memory cases once expected behavior is
  documented.
- `volume-column-effects.xm`: focused volume-column commands.

Each fixture should include a short source note explaining why it exists, what
rows/channels matter, and which tests may load it.

## Synthetic Instruments And Samples

Prefer generated or maintainer-authored sample data with simple, inspectable
properties:

- short sine wave for stable tonal payload.
- short square wave for easy edge and pitch inspection.
- click or drum transient for note start, cut, delay, and retrigger tests.
- looped steady-state waveform with clear loop boundaries.
- ping-pong loop waveform with non-symmetric endpoints.
- envelope-friendly sustained sample for volume and panning envelope tests.

Samples should be short, deterministic, and intentionally artificial. Avoid
musical phrases that could be confused with copied module content.

## Redistribution And Licensing

Rules for committed fixtures:

- Fixtures must be generated by the project or hand-authored by the maintainer.
- Fixture source and binary XM assets need a clear license statement, preferably
  inheriting the repository license unless a future design note says otherwise.
- Do not use private XM files, copied tracker modules, commercial sample
  material, copyrighted songs, or private corpus-derived assets.
- Do not derive samples, patterns, instrument names, order tables, or effect
  sequences from private modules.
- Do not require local absolute paths, private corpus maps, private filenames,
  or machine-specific setup in automated tests.

Any binary XM fixture commit should be explicit, small, and reviewed as a test
asset change.

## Reference Render Policy

Future reference WAVs may be useful for backend work after the temporary XM
backend foundation freeze, but this plan does not reopen backend work.

Policy:

- ft2-clone can be used locally to generate FT2-style reference WAVs.
- Generated WAV, JSON, Markdown, trace, log, and screenshot artifacts should
  stay under `/tmp` or another ignored local path unless a future PR explicitly
  approves committing them.
- Prefer committing fixture source, generator scripts, compact metrics, and
  documented renderer settings before committing large binary WAVs.
- Do not commit reference WAVs unless they are small, redistributable, valuable
  for CI, and reviewed in a dedicated PR.

Reference renders are diagnostic evidence. They do not by themselves justify
C mixer DSP, runtime backend, parser architecture, playback planning, or
tracker viewport changes during the freeze.

## Generation Strategy

Hand-authored XMs are acceptable when the provenance is clear, the file is
small, and the source notes are reviewable. Generator scripts are preferable
where practical because they make binary XM contents reproducible.

Future generator rules:

- Keep scripts deterministic and tested.
- Document generator inputs, sample formulas, and expected output paths.
- Write generated local reports and trial renders outside the repository.
- Commit binary XM outputs only in explicit fixture PRs.
- Update `tests/reference-xm/README.md` and relevant tests when adding a
  fixture.

## Editor Support

The pack should unblock future editor work without calling audio backends from
editor paths in this planning PR.

Expected future coverage:

- selected instrument/sample display against real loaded-module payload.
- positive note audition preview availability with loaded-module samples.
- preview-only key release and key-off routing without pattern mutation.
- sample editor fixtures for loop boundaries, sample length, and waveform
  display.
- instrument editor fixtures for sample maps, envelopes, and metadata.
- pattern loop while editing with tiny, predictable order/pattern layouts.

Blank documents may still remain preview-unavailable until import, sample
loading, or editor-created payload exists.

## Backend Support After Freeze

After a documented freeze-exit criterion is met, these fixtures can support
backend validation by isolating effect families and sample behaviors without
private-corpus dependence:

- ft2-clone comparison with documented local renderer settings.
- bounded render comparison through the existing offline render/export path.
- effect-family isolation for pitch, volume, traversal, retrigger/cut/delay,
  effect memory, and volume-column behavior.
- regression tests that use public fixtures instead of private modules.

This plan does not change offline render output, runtime playback, C mixer DSP,
backend selection, playback planning, XM effects, parser architecture, tracker
viewport math, editor note entry, note audition audio, or file save/export.

## Phased Plan

1. Add `tests/reference-xm/README.md` with license/provenance rules and the
   first generator-script contract. Done.
2. Add a minimal generator skeleton and matching deterministic source
   manifest, without binary XM output. Done.
3. Add `basic-instrument-sample.xm` plus parser/editor tests that prove real
   sample payload can be loaded from a public fixture. Done.
4. Add `multi-pattern-loop-boundary.xm` plus loader, builder, and runtime
   adapter-plan tests for public-safe multi-pattern order traversal. Done.
5. Add the manifest-driven generator/verification foundation and
   `instrument-sustained-defaults.xm`. Done.
6. Add `instrument-metadata-matrix.xm` as the dependent second instrument-pack
   PR. Done.
7. Add `instrument-envelopes-keymap.xm` as the dependent third instrument-pack
   PR, preserving unsupported empty/sample-less states honestly. Done.
8. Add preview, isolated loop, and envelope fixtures where the three landed
   instrument modules do not already cover the focused test need.
9. Add effect-family fixtures after expected behavior is documented and the
   backend freeze posture allows the relevant validation work.
10. Decide separately whether compact metrics or reference WAVs belong in git.

## Acceptance Checklist For Future Fixture PRs

- Fixture provenance and license are documented.
- No private modules, private corpus maps, copied module content, local paths,
  generated reports, traces, screenshots, or reference WAVs are committed unless
  explicitly approved for that PR.
- New binary XM files are small and reviewed as intentional test assets.
- Tests explain why each fixture exists.
- Backend, parser, tracker viewport, editor behavior, and file-format
  assumptions change only when explicitly in scope.

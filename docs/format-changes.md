# Format and Compatibility Changes

This log records intentional changes to VTX's supported persistence or module
compatibility boundary. It is not a claim of arbitrary XM round-trip support.

## Native C playback-head diagnostics

Normal full-plan and explicit user-Loop transport follow now uses one C-head
observation. The raw runtime frame is the next unrendered C sample, not the
CoreAudio device or audible clock; exact row boundaries select the next interval
without subtracting a frame. Normal
sample-time follow retains its existing mapped planned-frame meaning separately
from the raw C frame. Existing event/source numeric IDs are not redefined.

Playback-follow diagnostics add `terminal` and `capture_unavailable` status
values. `terminal` explicitly clamps the last musical row/tick during fault
retirement or silence while retaining the observed raw head. C reaches the
retirement end, then further silence buffers do not advance its frame. The
control-side result distinguishes captured, notRendered and unavailable.
`capture_unavailable` means a last-known coordinate could not be refreshed when
host quiescence or head capture fails; its stored frame is not a claim of current
audio position. Pause retains that tagged row as its fallback resume context.
Consumers must retain these
statuses rather than treating either as ordinary `in_range` evidence. Before any
rendered head exists, the selected cold context remains the navigation intent.

This changes diagnostic interpretation and corrects live/Stop/Pause position
values. Trace field shapes and event/source identity meanings remain compatible;
MOD/XM bytes, parsing, editable persistence and WAV encoding do not change. No
stored-document migration is required.

## Native user-Loop runtime trace scope

Runtime trace `schemaVersion: 1` gains optional `loopOccurrence` and
`loopOccurrenceSummary` objects for explicit user Loop. Normal trace rows omit
both objects; existing event/source ID meanings and full-plan control fixtures
are unchanged.
The new occurrence key is exact document/source/transport/rate/mode/loop scope
plus batch sequence, original event ordinal and numeric event ID. A local source
lookup index remains separate from its full birth-generation/sequence/index
binding; wrap does not fabricate a source or renumber an event.

Capsules are drained after host stop and before Core reset. They are deferred
observations from a fixed ring, whose dropped-capsule total is explicit. The
existing consumed counter retains its raw-unique-ID meaning: live values cover
acknowledged retired batches; final Stop also includes active partial execution.
Occurrence attempted/applied/suppressed/failed totals are separate.

Trace readers preserve these scopes and exclude native capsules from legacy
full-plan application counts. Window correlation rejects an unscoped offline
identity/effect oracle for a scoped Loop trace; audio/frame-only inspection
remains available. MOD/XM bytes, parsing and editable persistence are unchanged;
no stored-document migration is required.

## XM pattern-local looping (G38B)

The approved composition policy gives every pattern its own executed E60 anchor
or implicit row 0 and independent per-channel repeat counters; natural pattern
entry is row 0. This intentionally excludes FT2's numeric-anchor/counter leakage
and stale next-entry row. G38A ordered B/D/E6/EE precedence remains unchanged.
The earlier song-wide executed-E60 flag no longer suppresses another pattern's
implicit loop. Existing safe break bounds, long-pattern targets, finite guards
and bounded one-pass restart behavior retain their documented scope.

[The bounded policy](xm-effect-support.md#bounded-g38b-pattern-local-loop-and-traversal-policy)
and original synthetic Swift/runtime regressions define the compatibility
boundary. MOD/XM bytes, parsing and editable persistence do not change; no stored
format or document migration is required. Live start-aware planning stays #516.

## Disposable local corpus inventory v1

`corpus_map enrich` introduces a separate generated JSON artifact with
`schema_version: 1`, label-oriented `entries`, and SHA-256 `duplicate_groups`.
The stable input label map and existing updater outputs keep their schemas and
behavior. The inventory contains structural facts, not current support/closure
classifications or source paths. Static inspection and unchecked VTX admission
remain distinct; see [diagnostic tooling](diagnostic-tools.md#regenerable-corpus-inventory).
No migration is required: regenerate this disposable artifact from the explicit
local map. Synthetic tests verify byte determinism, unchanged inputs, existing
walker compatibility, redaction, output confinement, and candidate selection.

## XM tick-domain envelope diagnostics

Bounded-render JSON now identifies XM envelope state with
`clock_policy: canonical_fxx_tick_plan` and `position_domain: xm_ticks`.
`semantic_targets` contains source coordinates, event/channel identity, tick,
scheduled frame, current BPM/speed, logical volume/pan positions, key state,
integer fadeout accumulator and held envelope/fadeout factors. Snapshots add
`position_tick` and `fadeout_accumulator`; top-level snapshot fields add
`envelope_position_tick_at_start` and `envelope_position_tick_at_key_off`.

For this clock policy, obsolete frame-position/after-advance/segment/loop-count
snapshot fields and `fadeout_frame_decrement` are null. Use the tick fields and
`fadeout_tick_decrement` instead. Static point-frame arrays retain their legacy
trigger-tempo projection, explicitly marked by
`point_mapping_policy: legacy_trigger_frame_projection`; they do not govern
playback. Generic synthetic frame-envelope diagnostics retain their existing
fields and policies. Consumers must inspect the clock policy before treating
a position or fadeout rate as frame-domain data.

Focused JSON tests cover the new policy, null legacy fields, exact targets and
identity. Generic envelope/reset tests preserve the frame-domain path. This
changes generated diagnostic output only: MOD/XM parsing, module bytes, editable
documents and WAV encoding have no format change or required migration.

## Sparse sample-slot XM export foundation

Status: implemented for the supported editable XM subset.

The editable model keeps represented `PlaybackSample` values sparse and uses
their zero-based `sampleIndex` as canonical identity. Export XM now chooses each
instrument's serialized sample-header count as:

```text
max(highest represented sampleIndex, highest exact-keymap sampleIndex) + 1
```

when either identity exists, capped at S16/index 15. A true sampleless instrument
without an explicit map keeps its existing zero-sample header.

Each missing position inside the span is written as one ordinary 40-byte XM
sample header whose bytes are all zero: zero payload and loop lengths, zero
volume/finetune/type/panning/relative-note/reserved values, and an empty name.
It has no PCM payload and is never represented in memory as a sample. Exact
96-entry keymap values are emitted directly without compaction or remapping.

The normal loader omits these zero-length headers while retaining later sample
indices and the exact map, so mapped empty routes reopen unavailable without
fallback. Existing dense alpha.1 output remains byte-identical. Duplicate or
out-of-capacity identities, malformed/out-of-capacity maps, and prior writer
safety failures remain typed validation errors before atomic replacement.

The normal XM instrument walker now retains source-only provenance for each
sample-header index: the decoded payload length and whether the declared header
is exactly 40 bytes of zero. Make Editable Copy allows missing identities only
when that indexed provenance exactly covers the writer-required span and every
missing header is canonical. The existing production writer dry-run and Linear-
frequency-table requirement still apply.

VTX sparse export -> normal reopen -> Make Editable Copy -> re-export now
preserves interior gaps, trailing mapped empty slots, only-empty mapped S01,
represented sample metadata/PCM, and the exact keymap without fabrication or
compaction; focused cases re-export byte-identically. A named, metadata-bearing,
extended, extra trailing, or otherwise noncanonical zero-length source header
remains copy-unavailable rather than being silently canonicalized. This supports
canonical sparse empty sample slots, not zero-length samples generally.

No migration tool is required: the output is standard XM structural state,
existing dense exports do not change, no native VTX format exists, and no stored
VTX document requires conversion. Compatibility is covered by byte-stability,
writer/reopen, resolver, atomic export, capacity, provenance classification,
negative noncanonical-header, and editable-copy/re-export tests.

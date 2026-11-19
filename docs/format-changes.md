# Format and Compatibility Changes

This log records intentional changes to VTX's supported persistence or module
compatibility boundary. It is not a claim of arbitrary XM round-trip support.

## Policy B ordinary absent-keymap routing

Ordinary explicit-note sources and tone targets now refuse nil keymaps rather
than selecting the first playable sample. This applies equally to editable value
snapshots and loaded read-only representations, including short/partial sampled
XM headers. The exact 96-entry map remains the only admitted route; mapped
missing/empty identities retain their separate existing behavior. Nil does not
acquire a mapped-empty cut of a prior voice.

This implements [accepted Policy B](decisions/012-from-scratch-instrument-sample-composition-model.md#accepted-superseding-routing-clarification-policy-b).
Loaded bytes, parser behavior, provenance, writer output and editable-copy
admission are unchanged; no stored-format migration is required. No read-only
fallback exception is approved. Clear Song Data's nil-plus-PCM bridge and the
writer's nil-to-S01 serialization remain separate open contracts.

## Native C playback-head diagnostics

Normal full-plan, finite continuation and explicit user-Loop transport follow use one C-head
observation. The raw runtime frame is the next unrendered C sample, not the
CoreAudio device or audible clock; exact row boundaries select the next interval
without subtracting a frame. Normal
sample-time follow retains its existing mapped planned-frame meaning separately
from the raw C frame. Existing event/source numeric IDs are not redefined.

Playback-follow diagnostics add `terminal` and `capture_unavailable` status
values. `terminal` explicitly clamps the last musical row/tick during fault
retirement or silence while retaining the observed raw head. Fault retirement
stops advancing C at its retirement end. Successful finite song completion
clears voices at the existing tail deadline and continues the normal silent C
sample clock until host Stop; it does not enter fault retirement. The
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
`loopOccurrenceSummary` objects for explicit user Loop. Existing full-plan rows omit
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

## Version 2 finite-song native diagnostic IDs

Bounded ordinary-song occurrence and summary records use `schemaVersion: 2`
with required `nativeTransportKind: "finite_song"`. They reuse the existing
`loopOccurrence` and `loopOccurrenceSummary` envelope fields. These historical
wire names identify scoped native data; they do not make ordinary playback a
user-pattern Loop. Occurrence scope also requires `transportKind: "finite_song"`.
Explicit user Loop remains version 1 and omits both kind fields, preserving its
existing encoded scope. Full-plan runtime and offline numeric IDs and JSON retain
their established meanings.

Version 2 numeric event IDs and source lookup indices are immutable batch-local
keys. Occurrence identity includes transport kind, exact document/source/transport/
rate/frequency-mode scope, batch sequence, event ordinal and numeric ID. Imported
commands retain their original full birth-generation/transport/sequence/index
binding; a later batch does not fabricate a new note or redirect its sample.
Ordinary scope's order/pattern/row-range fields describe the admitted launch
selection, not bounds on later cross-order source coordinates. Each occurrence
retains its actual source order, pattern and row.

Updated readers require the version/kind combination and matching finite scope,
reject unknown or missing discriminators without a legacy-ID fallback, and keep
`ordinary_native` separate from `user_loop_native` summaries. Their canonical
keys include the explicit transport kind even for version 1 Loop input. Raw
unique-ID consumption, executed occurrence totals, and dropped observations remain
distinct; no raw ID alone may be joined to a whole-song offline event.
Finite playback omits the legacy `consumedPlannedEventCount` while active and
does not merge its local ID union into that counter on Stop. Scoped occurrence
totals are its progress evidence; explicit Loop's existing raw-ID counter remains
unchanged.

The existing scoped envelope fields keep older readers conservative: readers
that recognize those fields continue excluding scoped rows from legacy planned
application counts and rejecting unscoped offline identity/effect correlation.
Older readers do not fully understand version 2: they label the shared envelope
as Loop and may omit transport kind from their keys. Use updated readers for
ordinary or mixed-mode interpretation. Audio/frame-only window inspection remains
available; a complete scoped execution oracle is still required for identity joins.

This is a diagnostic identity change, not permission to reorder equal-frame
musical writers or alter sample/source ownership. Compatibility tests pin version
1 encoding, version 2 scope and birth identity, mode separation, exact UInt64s,
drop accounting and refusal of unscoped joins. Full-plan semantic/native-frame/PCM
parity remains a separate required gate. MOD/XM bytes, parsing, editable persistence
and audio encoding do not change; no stored-document migration is required.

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

## Clear Song Data palette admission

The loaded read-only bridge now refuses the whole palette when any retained
instrument has represented PCM and no keymap. Exact maps, sparse identities and
retained neutral instruments are unchanged. No parser, XM byte layout, writer,
normalization profile or stored document changes; no migration is required.
The writer's independent nil-to-all-S01 behavior remains an open contract.

# Format and Compatibility Changes

This log records intentional changes to VTX's supported persistence or module
compatibility boundary. It is not a claim of arbitrary XM round-trip support.

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

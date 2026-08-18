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

Loaded XM state does not retain source zero-length-header provenance. Make
Editable Copy therefore retains its dense represented-sample/map eligibility
guard; a reopened sparse VTX export remains read-only and copy-unavailable for
now. Unreferenced trailing zero-length source headers remain indistinguishable
after load, as before this change; newly represented sparse state does not become
eligible. This avoids widening arbitrary-source compatibility through a lossy
copy.

No migration tool is required: the output is standard XM structural state,
existing dense exports do not change, no native VTX format exists, and no stored
VTX document requires conversion. Compatibility is covered by byte-stability,
writer/reopen, resolver, atomic export, capacity, and editable-copy guard tests.

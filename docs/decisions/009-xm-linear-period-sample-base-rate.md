# ADR 009: XM Linear Period Sample Base Rate

## Status

Accepted for the Swift adapter/runtime planning layer.

## Context

VoodooTracker X converts parsed XM notes into generic C mixer sample-step
updates in Swift. The C mixer consumes the resulting step values; it does not
own XM period or frequency-table semantics.

The FastTracker 2 v2.04 XM format documentation's frequency table defines the
linear path as pattern note plus sample relative note, clamped to the
zero-based real-note range `0...118`. The linear period is:

```text
period = 7680 - realNote * 64 - finetune / 2
```

C-4 is note value 49, zero-based real note 48, and period 4608. The linear
frequency is anchored at 8363 Hz:

```text
frequency = 8363 * 2 ^ ((4608 - period) / 768)
```

## Decision

Keep XM linear-period, frequency, finetune, `E5x`, and output sample-rate
conversion in the Swift adapter/runtime planning layer.

Keep the parsed XM sample base rate at 8363 Hz for linear-table scheduling. In
this path it is the FT2 C-4 base-frequency anchor, not a per-sample property
parsed from XM sample headers.

Clamp `note + relativeNote` to the FT2 real-note range by preserving the
adapter's existing one-based diagnostic convention as values `1...119`.

## Rationale

The expected-value tests match the FT2 XM frequency-table equations and the
legacy VoodooTracker pitch anchor. The current VTX equation and fixed 8363 Hz
anchor were correct for ordinary in-range notes. The incorrect behavior was
only the effective-note clamp: capping at `1...96` treated the pattern note
range as the final real-note range and under-pitched samples whose relative
note transposed high notes beyond B-7.

## Consequences

- high positive relative-note samples can now schedule above pattern note 96
  within the XM real-note range
- existing C-0 through B-7 behavior remains unchanged unless relative note
  pushes the real note outside that old pattern-note cap
- C mixer DSP, interpolation, loop stepping, runtime backend defaults, parser
  architecture, tracker viewport behavior, gain policy, and envelope/fadeout
  semantics remain unchanged
- private/local comparison modules and generated diagnostics remain outside git

## References

- FastTracker 2 v2.04 XM format documentation, frequency table:
  <https://ftp.modland.com/pub/documents/format_documentation/FastTracker%202%20v2.04%20%28.xm%29.html>

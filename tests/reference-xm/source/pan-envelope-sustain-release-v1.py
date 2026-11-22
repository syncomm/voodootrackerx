#!/usr/bin/env python3
"""Public PAN-SR characterization recipe v1; no reference-derived bytes or policy assertions."""
import argparse
import hashlib
import json
from pathlib import Path
import struct


def cases():
    """Isolate clock boundaries, release dispatch, positioning and source existence."""
    result = {}

    def add(name, **options):
        result[name] = options

    add('held-interior')
    add('held-last', points=[(0, 32), (4, 16)])
    add('held-disabled', pan_flags=0)
    add('held-no-sustain', pan_flags=1)
    for kind in ['note97', 'k00']:
        for timing, ordinal in [('before', 6), ('at', 12), ('after', 18)]:
            add(f'{kind}-{timing}', points=[(0, 32), (12, 16), (16, 48), (20, 32)],
                release=(kind, ordinal), control='held-long')
        add(f'{kind}-held-release', release=(kind, 6), control='held-interior')
    add('held-long', points=[(0, 32), (12, 16), (16, 48), (20, 32)])
    for timing, ordinal in [('before', 3), ('at', 4), ('after', 5)]:
        add(f'kxx-{timing}', release=('kxx', ordinal), control='held-interior')
        add(f'last-kxx-{timing}', points=[(0, 32), (4, 16)],
            release=('kxx', ordinal), control='held-last')
    add('disabled-release', pan_flags=0, release=('note97', 6), control='held-disabled')
    add('no-sustain-release', pan_flags=1, release=('note97', 6), control='held-no-sustain')
    add('loop-control', pan_flags=5, loop=(1, 2))
    add('loop-release', pan_flags=5, loop=(1, 2), release=('note97', 6), control='loop-control')
    for location, sustain in [('start', 1), ('end', 2)]:
        control = f'loop-{location}-held'
        add(control, pan_flags=7, loop=(1, 2), sustain=sustain)
        for timing, ordinal in [('before', 3 if location == 'start' else 6),
                                ('at', 4 if location == 'start' else 8),
                                ('after', 6 if location == 'start' else 12)]:
            add(f'loop-{location}-{timing}', pan_flags=7, loop=(1, 2), sustain=sustain,
                release=('kxx' if ordinal % 6 else 'note97', ordinal), control=control)
    for flags in [1, 3, 0, 2]:
        for relation, ordinal in [('same', 12), ('before', 6), ('after', 18), ('control', None)]:
            # Disabled-volume cases isolate the raw gate; same-cell plus control suffices.
            if flags in [0, 2] and relation in ['before', 'after']:
                continue
            control = f'lxx8-v{flags}-control'
            add(f'lxx8-v{flags}-{relation}', volume_flags=flags, lxx=(2, 8),
                release=None if ordinal is None else ('note97', ordinal), control=control)
    for released in [False, True]:
        add('lxx4-' + ('release' if released else 'control'), volume_flags=3, lxx=(2, 4),
            release=('note97', 12) if released else None, control='lxx4-control')
    for source in ['zero-volume', 'empty']:
        for released in [False, True]:
            add(f'{source}-' + ('release' if released else 'control'), source=source,
                release=('note97', 6) if released else None, control=f'{source}-control')
    for action in ['note-only', 'instrument-only', 'ed1-instrument-only']:
        for released in [False, True]:
            add(f'{action}-' + ('release' if released else 'control'), action=action,
                release=('note97', 6) if released else None, control=f'{action}-control')
    add('long-clock-wrap', long=True, release=('note97', 6), control='held-interior')
    add('tone-control', source='tone')
    add('tone-release', source='tone', release=('note97', 6), control='tone-control')
    add('tone-recover', source='tone', release=('note97', 6), lxx=(2, 8), volume_flags=3,
        control='tone-control')
    return result


def module(linear, options):
    """Encode an original two-channel XM with exact S01 or empty S02 routing."""
    points = options.get('points', [(0, 32), (4, 16), (8, 48), (12, 32)])
    source = options.get('source', 'pcm')
    events = {(0, 0): (49, 1, 0, 0, 0)}
    release = options.get('release')
    if release:
        kind, ordinal = release
        row, tick = divmod(ordinal, 6)
        prior = events.get((row, 0), (0, 0, 0, 0, 0))
        events[row, 0] = (97, 0, 0, 0, 0) if kind == 'note97' else (*prior[:3], 20, tick)
    if 'lxx' in options:
        row, position = options['lxx']
        cell = events.get((row, 0), (0, 0, 0, 0, 0))
        events[row, 0] = (*cell[:3], 21, position)
    if source == 'zero-volume':
        events[3, 0] = (0, 0, 0, 12, 64)
    action = options.get('action')
    if action:
        events[2, 0] = {'note-only': (49, 0, 0, 0, 0),
                        'instrument-only': (0, 1, 0, 0, 0),
                        'ed1-instrument-only': (0, 1, 0, 14, 0xD1)}[action]
    rows = 256 if options.get('long') else 8
    header = bytearray(336)
    header[:17] = b'Extended Module: '
    header[17:37] = b'VTX PAN SR V1'.ljust(20, b' ')
    header[37], header[38:58] = 26, b'VTX PUBLIC RECIPE'.ljust(20, b' ')
    struct.pack_into('<HI8H', header, 58, 0x104, 276, 44 if options.get('long') else 1,
                     0, 2, 2 if options.get('long') else 1, 1, int(linear), 6, 125)
    if options.get('long'):
        header[81:124] = bytes([1]) * 43
    pattern = bytearray()
    for row in range(rows):
        for channel in range(2):
            cell = events.get((row, channel), (0, 0, 0, 0, 0))
            fields = [(1 << i, value) for i, value in enumerate(cell) if value]
            pattern.append(128 + sum(flag for flag, _ in fields))
            pattern.extend(value for _, value in fields)
    instrument = bytearray(263)
    struct.pack_into('<I', instrument, 0, 263)
    instrument[4:26] = b'PUBLIC PAN SR'.ljust(22, b'\0')
    struct.pack_into('<HI', instrument, 27, 2 if source == 'empty' else 1, 40)
    if source == 'empty':
        instrument[33:129] = bytes([1]) * 96
    struct.pack_into('<HHHH', instrument, 129, 0, 64, 96, 64)
    for index, (tick, value) in enumerate(points):
        struct.pack_into('<HH', instrument, 177 + 4 * index, tick, value)
    instrument[225], instrument[226] = 2, len(points)
    instrument[227], instrument[230] = 1, options.get('sustain', 1)
    instrument[231], instrument[232] = options.get('loop', (0, 0))
    instrument[233], instrument[234] = options.get('volume_flags', 1), options.get('pan_flags', 3)
    sample = bytearray(40)
    struct.pack_into('<III', sample, 0, 256, 0, 256)
    sample[12], sample[14], sample[15] = 0 if source == 'zero-volume' else 64, 1, 128
    sample[18:40] = b'CONSTANT LOOP S01'.ljust(22, b'\0')
    pcm = [32] * 256
    if source == 'tone':
        sample[18:40] = b'STEADY TRIANGLE S01'.ljust(22, b'\0')
        pcm = [64 - 8 * abs(i % 32 - 16) for i in range(256)]
    empty = bytearray(40) if source == 'empty' else bytearray()
    if empty:
        empty[12], empty[15] = 64, 128
        empty[18:40] = b'EMPTY S02'.ljust(22, b'\0')
    patterns = struct.pack('<IBHH', 9, 0, rows, len(pattern)) + pattern
    if options.get('long'):
        # A neutral F06 prevents reference-loader empty-pattern shortening to 64 rows.
        blank = bytes([128]) * (rows * 2 - 1) + bytes([0x98, 15, 6])
        patterns += struct.pack('<IBHH', 9, 0, rows, len(blank)) + blank
    payload, previous = bytearray(), 0
    for value in pcm:
        payload.append((value - previous) & 255)
        previous = value
    return bytes(header) + patterns + instrument + sample + empty + payload


def main():
    """Write deterministic fixtures and optionally verify the versioned hash manifest."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', required=True, type=Path)
    parser.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    output = args.output_dir.expanduser().resolve()
    if not output.is_relative_to(Path('/private/tmp')):
        parser.error('Use an explicit /private/tmp output directory (or /tmp alias).')
    fixtures, metadata = {}, {}
    for case, options in cases().items():
        for mode, linear in [('linear', True), ('amiga', False)]:
            name = f'pan-sr-v1-{case}-{mode}.xm'
            fixtures[name] = module(linear, options)
            metadata[name] = dict(case=case, mode=mode, **options)
    hashes = ''.join(f'{hashlib.sha256(data).hexdigest()}  {name}\n'
                     for name, data in sorted(fixtures.items()))
    if args.verify and hashes != Path(__file__).with_suffix('.sha256').read_text():
        parser.error('Recipe v1 hashes differ from the proposed source manifest.')
    output.mkdir(parents=True, exist_ok=True)
    for name, data in fixtures.items():
        (output / name).write_bytes(data)
    (output / 'SHA256SUMS.txt').write_text(hashes)
    (output / 'matrix.json').write_text(json.dumps(metadata, indent=2) + '\n')
    print(f'Generated {len(fixtures)} public recipe-v1 inputs; hashes verified={args.verify}.')


if __name__ == '__main__':
    main()

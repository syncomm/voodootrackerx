#!/usr/bin/env python3
"""Public pan-Q8 recipe v1. Generate external XM controls; no reference/private data."""
import argparse
import hashlib
from pathlib import Path
import struct


def instrument(points, arrival=None, volume_flags=0, header_volume=64, music=False):
    header = bytearray(263)
    struct.pack_into('<I', header, 0, 263)
    header[4:26] = (b'OLD PAN' if arrival is None else b'NEW PAN').ljust(22, b'\0')
    struct.pack_into('<HI', header, 27, 1, 40)
    for index, (tick, value) in enumerate(points):
        struct.pack_into('<HH', header, 177 + 4 * index, tick, value)
    header[226], header[234] = len(points), int(bool(points))
    if volume_flags:
        struct.pack_into('<HHHH', header, 129, 0, 64, 20, 64)
        header[225], header[227], header[233] = 2, 1, volume_flags
    if music and points:
        header[231], header[232], header[234] = 0, len(points) - 1, 5
    pcm = [32] * 16 if not music else [48 - 6 * abs(16 - i) for i in range(32)]
    sample = bytearray(40)
    struct.pack_into('<III', sample, 0, len(pcm), 0, len(pcm))
    sample[12], sample[14], sample[15] = header_volume, 1, 128
    sample[18:40] = (b'CONSTANT16' if not music else b'TRIANGLE32').ljust(22, b'\0')
    previous, payload = 0, bytearray()
    for value in pcm:
        payload.append((value - previous) & 255)
        previous = value
    return bytes(header + sample + payload)


def module(linear, points, commands=None, second=None, rows=8, volume_flags=0,
           header_volume=64, music=False):
    header = bytearray(336)
    header[:17] = b'Extended Module: '
    header[17:37] = (b'VTX PAN CARRY V1' if not music else b'VTX PAN Q8 STUDY').ljust(20, b' ')
    header[37], header[38:58] = 26, b'VTX PUBLIC RECIPE'.ljust(20, b' ')
    struct.pack_into('<HI8H', header, 58, 0x104, 276, 1, 0, 2, 1,
                     1 + int(second is not None), int(linear), 6, 125)
    events = {(0, 0): (49, 1, 0, 0, 0)} | (commands or {})
    if music:
        events = {(row, channel): (note, channel + 1 if row == 0 else 0, 0, 0, 0)
                  for row, lead, bass in [(0, 49, 25), (4, 53, 29), (8, 56, 32), (12, 60, 36)]
                  for channel, note in [(0, lead), (1, bass)]}
    packed = bytearray()
    for row in range(rows):
        for channel in range(2):
            cell = events.get((row, channel), (0, 0, 0, 0, 0))
            fields = [(1 << i, value) for i, value in enumerate(cell) if value]
            packed.append(128 + sum(flag for flag, _ in fields))
            packed.extend(value for _, value in fields)
    pattern = struct.pack('<IBHH', 9, 0, rows, len(packed)) + packed
    result = bytes(header) + pattern + instrument(points, volume_flags=volume_flags,
                                                  header_volume=header_volume, music=music)
    if second is not None:
        result += instrument(second, arrival=True, music=music, header_volume=24 if music else 64)
    return result


def fixtures():
    """Return deterministic input bytes, including the original 993-byte wrap witness."""
    positive, negative = [(0, 13), (6, 14), (13, 61), (20, 17)], [(0, 61), (7, 13), (20, 57)]
    carry = {(1, 0): (0, 2, 0, 0, 0), (2, 0): (49, 0, 0, 0, 0)}
    cases = {
        'positive': dict(points=positive), 'negative': dict(points=negative),
        'point64': dict(points=[(0, 13), (7, 64), (20, 17)]),
        'from64': dict(points=[(0, 64), (7, 13), (20, 57)]),
        'endpoints': dict(points=[(0, 0), (3, 63), (10, 0)]),
        'neutral': dict(points=[(0, 32), (20, 32)]),
        'lxx-on': dict(points=positive, commands={(1, 0): (0, 0, 0, 21, 4)}, volume_flags=2),
        'lxx-off': dict(points=positive, commands={(1, 0): (0, 0, 0, 21, 4)}),
        'carry-normal': dict(points=[(0, 13), (7, 19)], second=[(0, 13), (13, 29)], commands=carry),
        'carry-wrap': dict(points=[(0, 13), (7, 61)], second=[(0, 13), (13, 61)], commands=carry, rows=3),
        'reset': dict(points=positive, commands={(1, 0): (0, 1, 0, 0, 0)}),
        'zero-volume': dict(points=positive, header_volume=0, commands={(2, 0): (0, 0, 0, 12, 64)}),
        'sub-q8-positive': dict(points=[(0, 32), (512, 33)], rows=96),
        'sub-q8-negative': dict(points=[(0, 33), (512, 32)], rows=96),
        'music': dict(points=[(0, 13), (7, 64), (14, 13), (21, 64)], second=[], rows=16, music=True, header_volume=32),
    }
    return {f'pan-q8-v1-{case}-{mode}.xm': module(linear, **arguments)
            for case, arguments in cases.items() for mode, linear in [('linear', True), ('amiga', False)]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', required=True, type=Path)
    parser.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    output = args.output_dir.expanduser().resolve()
    if not output.is_relative_to(Path('/private/tmp')):
        parser.error('Use an explicit /private/tmp output directory (or /tmp alias).')
    data = fixtures()
    hashes = ''.join(f'{hashlib.sha256(value).hexdigest()}  {name}\n' for name, value in sorted(data.items()))
    if args.verify and hashes != Path(__file__).with_suffix('.sha256').read_text():
        parser.error('Recipe v1 hashes differ from the reviewed source manifest.')
    output.mkdir(parents=True, exist_ok=True)
    for name, value in data.items():
        (output / name).write_bytes(value)
    (output / 'SHA256SUMS.txt').write_text(hashes)
    print(f'Generated {len(data)} public recipe-v1 controls; hashes {"verified" if args.verify else "written"}.')


if __name__ == '__main__':
    main()

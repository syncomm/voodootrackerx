#!/usr/bin/env python3
"""MIT project-authored pure-key-off fixture recipe, version 1; no external input."""
import argparse
import hashlib
from pathlib import Path
import struct

VERSION = 1


def module(linear, held):
    """Reproduce the minimal and EE2 public characterization witnesses exactly."""
    channels, count, target = (4, 6, 2) if held else (2, 2, 1)
    rows = [[[0] * 5 for _ in range(channels)] for _ in range(count)]
    rows[0][0] = [49, 1, 0, 0, 0]
    rows[target][0] = [97, 0, 0, 14, 0xD1]
    rows[target][1] = [0, 0, 0, 14, 0xE2 if held else 0xE0]
    if held:
        rows[4][0] = [0, 0, 0, 20, 0]
    header = bytearray(336)
    header[:17] = b'Extended Module: '
    header[17:37] = b'VTX C14 PUBLIC V1'.ljust(20, b' ')
    header[37] = 26
    header[38:58] = b'ORIGINAL SYNTHETIC'.ljust(20, b' ')
    struct.pack_into('<HI8H', header, 58, 0x104, 276, 1, 0, channels, 1, 2, int(linear), 6, 125)
    cells = bytes(value for row in rows for cell in row for value in cell)
    data = bytes(header) + struct.pack('<IBHH', 9, 0, count, len(cells)) + cells
    for number in [1, 2]:
        instrument = bytearray(263)
        struct.pack_into('<I', instrument, 0, 263)
        instrument[4:26] = f'PUBLIC I{number}'.encode().ljust(22, b'\0')
        struct.pack_into('<HI', instrument, 27, 3, 40)
        mapping = [0] * 96
        mapping[50], mapping[52] = 2, 1
        instrument[33:129] = bytes(mapping)
        for offset, points in [(129, [(0, 64), (2, 48), (8, 16), (20, 0)]),
                               (177, [(0, 32), (2, 40), (8, 24), (20, 32)])]:
            for index, (tick, value) in enumerate(points):
                struct.pack_into('<HH', instrument, offset + 4 * index, tick, value)
        instrument[225] = instrument[226] = 4
        instrument[227] = instrument[230] = 1
        instrument[233] = instrument[234] = 3
        struct.pack_into('<H', instrument, 239, 256)
        headers, payload = [], bytearray()
        for slot in range(3):
            length = 0 if slot == 2 else 256
            sample = bytearray(40)
            struct.pack_into('<III', sample, 0, length, 0, length)
            sample[12] = [48 if number == 1 else 24, 32, 16][slot]
            sample[14], sample[15] = int(length > 0), [192 if number == 1 else 64, 96, 224][slot]
            sample[18:40] = f'PUBLIC I{number} S{slot + 1:02}'.encode().ljust(22, b'\0')
            headers.append(sample)
            previous = 0
            for frame in range(length):
                value = (48 - 6 * abs(frame % 32 - 16)) // (slot + 1)
                payload.append((value - previous) & 255)
                previous = value
        data += instrument + b''.join(headers) + payload
    return data


def main():
    """Regenerate outside the repository and verify the reviewed versioned hash manifest."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    output = args.output_dir.resolve()
    if not output.is_relative_to(Path('/private/tmp')):
        parser.error('Use an explicit /private/tmp output directory (or /tmp alias).')
    fixtures = {f'pure-delayed-keyoff-v1-{kind}-{mode}.xm': module(mode == 'linear', kind == 'held')
                for kind in ['minimal', 'held'] for mode in ['linear', 'amiga']}
    hashes = ''.join(f'{hashlib.sha256(data).hexdigest()}  {name}\n' for name, data in sorted(fixtures.items()))
    if hashes != Path(__file__).with_suffix('.sha256').read_text():
        parser.error('Version 1 fixture hashes differ from the reviewed manifest.')
    output.mkdir(parents=True, exist_ok=True)
    for name, data in fixtures.items():
        (output / name).write_bytes(data)
    print(f'Version {VERSION}: generated {len(fixtures)} public fixtures; SHA-256 verified.')


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""Scan a private XM corpus for residual effect-memory and volume-column gaps.

The scanner reads a local-only label map that contains private module paths, but
all generated output is public-safe: stable anonymized labels, frequency-table
classification, command counts, and source coordinates only.
"""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


DEFAULT_LABEL_MAP = Path("/tmp/vtx-private-xm-corpus-label-map.json")
DEFAULT_DOCS = Path("docs/xm-effect-support.md")
LABEL_RE = re.compile(r"^xm-corpus-(\d{3,})$")


class XMResidualScanError(Exception):
    """User-facing scanner error."""


@dataclass(frozen=True)
class Cell:
    note: int = 0
    instrument: int = 0
    volume: int = 0
    effect_type: int = 0
    effect_param: int = 0


@dataclass(frozen=True)
class Pattern:
    rows: list[list[Cell]]


@dataclass(frozen=True)
class InstrumentEnvelope:
    volume_enabled: bool = False


@dataclass(frozen=True)
class ModuleData:
    label: str
    frequency_table: str
    channels: int
    song_length: int
    default_speed: int
    default_bpm: int
    order_table: list[int]
    patterns: list[Pattern]
    instruments: list[InstrumentEnvelope]

    @property
    def volume_envelope_instrument_count(self) -> int:
        return sum(1 for instrument in self.instruments if instrument.volume_enabled)


@dataclass(frozen=True)
class Coordinate:
    label: str
    frequency_table: str
    order: int
    pattern: int
    row: int
    channel: int

    def text(self) -> str:
        return f"{self.label} order {self.order} pattern {self.pattern} row {self.row} ch {self.channel}"

    def to_json(self) -> dict[str, Any]:
        return {
            "label": self.label,
            "frequency_table": self.frequency_table,
            "order": self.order,
            "pattern": self.pattern,
            "row": self.row,
            "channel": self.channel,
            "text": self.text(),
        }


@dataclass
class ChannelState:
    active_voice: bool = False
    active_instrument: int | None = None
    tone_portamento_target: bool = False
    tone_portamento_speed: bool = False
    axy_memory: int | None = None


@dataclass
class FocusBucket:
    name: str
    counts: Counter = field(default_factory=Counter)
    by_label: Counter = field(default_factory=Counter)
    first_coordinate: Coordinate | None = None
    first_by_metric: dict[str, Coordinate] = field(default_factory=dict)
    family_counts: Counter = field(default_factory=Counter)
    input_labels: set[str] = field(default_factory=set)

    def add(
        self,
        label: str,
        coordinate: Coordinate,
        metric: str = "count",
        *,
        amount: int = 1,
        family: str | None = None,
    ) -> None:
        self.counts[metric] += amount
        self.by_label[label] += amount
        self.input_labels.add(label)
        if self.first_coordinate is None:
            self.first_coordinate = coordinate
        self.first_by_metric.setdefault(metric, coordinate)
        if family is not None:
            self.family_counts[family] += amount

    def count(self, metric: str = "count") -> int:
        return int(self.counts.get(metric, 0))

    def best_label(self) -> str:
        if not self.by_label:
            return "none"
        return sorted(self.by_label.items(), key=lambda item: (-item[1], label_number(item[0])))[0][0]

    def first_text(self, metric: str | None = None) -> str:
        coord = self.first_by_metric.get(metric or "") if metric else self.first_coordinate
        return coord.text() if coord else "none"

    def to_json(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "counts": dict(sorted(self.counts.items())),
            "family_counts": dict(sorted(self.family_counts.items())),
            "input_count": len(self.input_labels),
            "best_target_label": self.best_label(),
            "first_coordinate": self.first_coordinate.to_json() if self.first_coordinate else None,
            "first_by_metric": {
                key: value.to_json()
                for key, value in sorted(self.first_by_metric.items())
            },
        }


class ScanGroup:
    def __init__(self, name: str) -> None:
        self.name = name
        self.labels: set[str] = set()
        self.frequency_tables = Counter()
        self.buckets: dict[str, FocusBucket] = {
            "xxy": FocusBucket("Xxy extra fine portamento"),
            "lxx": FocusBucket("Lxx set envelope position"),
            "3xx": FocusBucket("3xx tone-portamento memory"),
            "axy": FocusBucket("Axy volume-slide memory"),
            "7xy": FocusBucket("7xy tremolo and tremolo memory"),
            "e0x": FocusBucket("E0x filter toggle"),
            "e3x": FocusBucket("E3x glissando control"),
            "eex": FocusBucket("EEx pattern delay"),
            "pxy": FocusBucket("Pxy panning slide"),
            "txy": FocusBucket("Txy tremor"),
            "vol_a": FocusBucket("Volume-column vibrato speed A0...AF"),
            "vol_b": FocusBucket("Volume-column vibrato depth B0...BF"),
            "vol_f": FocusBucket("Volume-column tone portamento F0...FF"),
            "rxy": FocusBucket("Rxy multi retrigger residuals"),
            "hxy": FocusBucket("Hxy global volume slide residuals"),
            "kxx": FocusBucket("Kxx key-off residuals"),
            "5xy": FocusBucket("5xy tone portamento + volume slide residuals"),
            "unknown": FocusBucket("Unknown/classification-only high bytes"),
            "amiga": FocusBucket("Amiga frequency-table foundation"),
        }

    def add_module(self, module: ModuleData) -> None:
        self.labels.add(module.label)
        self.frequency_tables[module.frequency_table] += 1

    def bucket(self, key: str) -> FocusBucket:
        return self.buckets[key]

    def to_json(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "module_count": len(self.labels),
            "frequency_table_counts": dict(sorted(self.frequency_tables.items())),
            "buckets": {key: bucket.to_json() for key, bucket in sorted(self.buckets.items())},
        }


def label_number(label: str) -> int:
    match = LABEL_RE.match(label)
    return int(match.group(1)) if match else 999_999


def utc_now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def u16(data: bytes, offset: int) -> int:
    if offset + 2 > len(data):
        raise XMResidualScanError("truncated XM u16 field")
    return int.from_bytes(data[offset : offset + 2], "little")


def u32(data: bytes, offset: int) -> int:
    if offset + 4 > len(data):
        raise XMResidualScanError("truncated XM u32 field")
    return int.from_bytes(data[offset : offset + 4], "little")


def parse_xm_module(path: Path, label: str, expected_frequency_table: str | None = None) -> ModuleData:
    try:
        data = path.read_bytes()
    except OSError as error:
        raise XMResidualScanError(f"could not read module for {label}: {error.strerror}") from error
    if len(data) < 336 or data[:17] != b"Extended Module: ":
        raise XMResidualScanError(f"{label} is not a readable XM module")

    header_size = u32(data, 60)
    song_length = u16(data, 64)
    channels = u16(data, 68)
    pattern_count = u16(data, 70)
    instrument_count = u16(data, 72)
    flags = u16(data, 74)
    default_speed = u16(data, 76)
    default_bpm = u16(data, 78)
    frequency_table = "linear" if flags & 0x01 else "amiga"
    if expected_frequency_table in {"linear", "amiga"} and expected_frequency_table != frequency_table:
        raise XMResidualScanError(f"{label} frequency table changed from label map metadata")
    order_table = list(data[80 : 80 + min(song_length, 256)])
    pattern_offset = 60 + header_size
    patterns, instrument_offset = parse_patterns(data, pattern_offset, pattern_count, channels, label)
    instruments = parse_instruments(data, instrument_offset, instrument_count)
    return ModuleData(
        label=label,
        frequency_table=frequency_table,
        channels=channels,
        song_length=song_length,
        default_speed=max(1, default_speed),
        default_bpm=max(32, default_bpm),
        order_table=order_table,
        patterns=patterns,
        instruments=instruments,
    )


def parse_patterns(
    data: bytes,
    offset: int,
    count: int,
    channels: int,
    label: str,
) -> tuple[list[Pattern], int]:
    patterns: list[Pattern] = []
    current = offset
    for pattern_index in range(count):
        if current + 9 > len(data):
            raise XMResidualScanError(f"{label} pattern {pattern_index} header is truncated")
        header_size = u32(data, current)
        if header_size < 9 or current + header_size > len(data):
            raise XMResidualScanError(f"{label} pattern {pattern_index} header is invalid")
        row_count = u16(data, current + 5)
        packed_size = u16(data, current + 7)
        packed_start = current + header_size
        packed_end = packed_start + packed_size
        if packed_end > len(data):
            raise XMResidualScanError(f"{label} pattern {pattern_index} packed data is truncated")
        rows = decode_pattern_cells(data[packed_start:packed_end], row_count, channels)
        patterns.append(Pattern(rows=rows))
        current = packed_end
    return patterns, current


def decode_pattern_cells(payload: bytes, row_count: int, channels: int) -> list[list[Cell]]:
    rows: list[list[Cell]] = []
    position = 0
    for _row in range(row_count):
        row_cells = []
        for _channel in range(channels):
            if position >= len(payload):
                row_cells.append(Cell())
                continue
            first = payload[position]
            position += 1
            if first & 0x80:
                note = read_packed_field(payload, first, 0x01, position)
                position = note[1]
                instrument = read_packed_field(payload, first, 0x02, position)
                position = instrument[1]
                volume = read_packed_field(payload, first, 0x04, position)
                position = volume[1]
                effect_type = read_packed_field(payload, first, 0x08, position)
                position = effect_type[1]
                effect_param = read_packed_field(payload, first, 0x10, position)
                position = effect_param[1]
                row_cells.append(Cell(note[0], instrument[0], volume[0], effect_type[0], effect_param[0]))
            else:
                values = [first]
                for _ in range(4):
                    if position < len(payload):
                        values.append(payload[position])
                        position += 1
                    else:
                        values.append(0)
                row_cells.append(Cell(*values))
        rows.append(row_cells)
    return rows


def read_packed_field(payload: bytes, flags: int, bit: int, position: int) -> tuple[int, int]:
    if not flags & bit:
        return (0, position)
    if position >= len(payload):
        return (0, position)
    return (payload[position], position + 1)


def parse_instruments(data: bytes, offset: int, count: int) -> list[InstrumentEnvelope]:
    instruments = [InstrumentEnvelope()]
    current = offset
    for _index in range(count):
        if current + 29 > len(data):
            instruments.append(InstrumentEnvelope())
            current = len(data)
            continue
        header_size = u32(data, current)
        if header_size < 29 or current + header_size > len(data):
            instruments.append(InstrumentEnvelope())
            current = min(len(data), current + max(29, header_size))
            continue
        sample_count = u16(data, current + 27)
        volume_enabled = False
        sample_header_size = 40
        if sample_count > 0 and header_size >= 234 and current + 234 <= len(data):
            sample_header_size = max(4, u32(data, current + 29))
            volume_point_count = data[current + 225]
            volume_type = data[current + 233]
            volume_enabled = bool(volume_type & 0x01) and volume_point_count > 0
        instruments.append(InstrumentEnvelope(volume_enabled=volume_enabled))

        headers_at = current + header_size
        headers_size = sample_count * sample_header_size
        data_size = 0
        if sample_count > 0 and headers_at + headers_size <= len(data):
            for sample_index in range(sample_count):
                data_size += u32(data, headers_at + sample_index * sample_header_size)
        current = min(len(data), headers_at + headers_size + data_size)
    return instruments


def xxy_family(param: int) -> str:
    command = (param >> 4) & 0x0F
    amount = param & 0x0F
    if command == 0x01:
        return "X1x extra fine portamento up" if amount else "X10 extra fine portamento up memory/no-op"
    if command == 0x02:
        return "X2x extra fine portamento down" if amount else "X20 extra fine portamento down memory/no-op"
    return f"X{command:X}x extension/classification"


def high_byte_label(effect_type: int) -> str:
    letters = {
        0x12: "Ixx",
        0x13: "Jxx",
        0x16: "Mxx",
        0x17: "Nxx",
        0x18: "Oxx",
        0x1A: "Qxx",
        0x1C: "Sxx",
        0x1E: "Uxx",
        0x1F: "Vxx",
        0x20: "Wxx",
        0x22: "Yxx",
        0x23: "Zxx",
    }
    return letters.get(effect_type, f"{effect_type:02X}xx")


def is_normal_note(note: int) -> bool:
    return 1 <= note <= 96


def instrument_has_volume_envelope(module: ModuleData, instrument: int | None) -> bool:
    if instrument is None or instrument <= 0 or instrument >= len(module.instruments):
        return False
    return module.instruments[instrument].volume_enabled


def scan_module(module: ModuleData, groups: list[ScanGroup]) -> None:
    for group in groups:
        group.add_module(module)

    states = [ChannelState() for _ in range(module.channels)]
    speed = max(1, module.default_speed)
    for order_index, pattern_index in enumerate(module.order_table[: module.song_length]):
        if pattern_index >= len(module.patterns):
            continue
        pattern = module.patterns[pattern_index]
        for row_index, row in enumerate(pattern.rows):
            next_speed = speed
            for channel_index in range(module.channels):
                cell = row[channel_index] if channel_index < len(row) else Cell()
                coordinate = Coordinate(module.label, module.frequency_table, order_index, pattern_index, row_index, channel_index)
                state = states[channel_index]
                scan_volume_column(module, cell, coordinate, groups)
                scan_effect_cell(module, cell, coordinate, state, speed, groups)
                if cell.effect_type == 0x0F and 0 < cell.effect_param < 0x20:
                    next_speed = max(1, cell.effect_param)
                apply_note_state(module, cell, state)
            speed = next_speed


def scan_volume_column(module: ModuleData, cell: Cell, coordinate: Coordinate, groups: list[ScanGroup]) -> None:
    raw = cell.volume
    if raw == 0:
        return
    if 0xA0 <= raw <= 0xAF:
        add_to_groups(groups, "vol_a", module.label, coordinate, family=f"A{raw & 0x0F:X}")
    elif 0xB0 <= raw <= 0xBF:
        add_to_groups(groups, "vol_b", module.label, coordinate, family=f"B{raw & 0x0F:X}")
    elif 0xF0 <= raw <= 0xFF:
        add_to_groups(groups, "vol_f", module.label, coordinate, family=f"F{raw & 0x0F:X}")
        if module.frequency_table == "amiga":
            add_to_groups(
                groups,
                "amiga",
                module.label,
                coordinate,
                metric="amiga_volume_column_fxx_count",
                family="volume-column tone portamento",
            )


def scan_effect_cell(
    module: ModuleData,
    cell: Cell,
    coordinate: Coordinate,
    state: ChannelState,
    speed: int,
    groups: list[ScanGroup],
) -> None:
    effect_type = cell.effect_type
    effect_param = cell.effect_param
    if effect_type == 0 and effect_param == 0:
        return
    if module.frequency_table == "amiga":
        scan_amiga_foundation(module, cell, coordinate, groups)
    if effect_type == 0x21:
        add_to_groups(groups, "xxy", module.label, coordinate, family=xxy_family(effect_param))
    elif effect_type == 0x15:
        scan_lxx(module, cell, coordinate, state, groups)
    elif effect_type == 0x03:
        scan_3xx(module, cell, coordinate, state, groups)
    elif effect_type == 0x0A:
        scan_axy(module, cell, coordinate, state, groups)
    elif effect_type == 0x07:
        scan_7xy(module, cell, coordinate, groups)
    elif effect_type == 0x0E:
        scan_extended_gap(module, cell, coordinate, groups)
    elif effect_type == 0x11:
        scan_hxy(module, cell, coordinate, groups)
    elif effect_type == 0x19:
        scan_pxy(module, cell, coordinate, groups)
    elif effect_type == 0x1B:
        scan_rxy(module, cell, coordinate, state, speed, groups)
    elif effect_type == 0x1D:
        scan_txy(module, cell, coordinate, groups)
    elif effect_type == 0x14:
        scan_kxx(module, cell, coordinate, state, speed, groups)
    elif effect_type == 0x05:
        scan_5xy(module, cell, coordinate, state, groups)
    elif effect_type in {
        0x12, 0x13, 0x16, 0x17, 0x18, 0x1A, 0x1C, 0x1E, 0x1F, 0x20, 0x22, 0x23,
    } or effect_type > 0x23:
        label = high_byte_label(effect_type)
        metric = "vxx_count" if effect_type == 0x1F else "wxx_count" if effect_type == 0x20 else "other_high_byte_count"
        add_to_groups(groups, "unknown", module.label, coordinate, metric=metric, family=label)


def scan_amiga_foundation(module: ModuleData, cell: Cell, coordinate: Coordinate, groups: list[ScanGroup]) -> None:
    if cell.effect_type == 0x02:
        add_to_groups(groups, "amiga", module.label, coordinate, metric="amiga_2xx_count", family="2xx portamento down")
    elif cell.effect_type == 0x03:
        add_to_groups(groups, "amiga", module.label, coordinate, metric="amiga_3xx_count", family="3xx tone portamento")
    elif cell.effect_type == 0x05:
        add_to_groups(groups, "amiga", module.label, coordinate, metric="amiga_5xy_count", family="5xy tone portamento + volume slide")
    elif cell.effect_type == 0x21:
        add_to_groups(groups, "amiga", module.label, coordinate, metric="amiga_xxy_count", family=xxy_family(cell.effect_param))
    elif cell.volume and 0xF0 <= cell.volume <= 0xFF:
        add_to_groups(groups, "amiga", module.label, coordinate, metric="amiga_volume_column_fxx_count", family="volume-column tone portamento")


def scan_lxx(
    module: ModuleData,
    cell: Cell,
    coordinate: Coordinate,
    state: ChannelState,
    groups: list[ScanGroup],
) -> None:
    add_to_groups(groups, "lxx", module.label, coordinate)
    same_cell_envelope = instrument_has_volume_envelope(module, cell.instrument)
    active_envelope = instrument_has_volume_envelope(module, state.active_instrument)
    if module.volume_envelope_instrument_count > 0:
        add_to_groups(groups, "lxx", module.label, coordinate, metric="module_has_volume_envelope_count")
    if same_cell_envelope:
        add_to_groups(groups, "lxx", module.label, coordinate, metric="same_cell_envelope_enabled_count")
    if active_envelope:
        add_to_groups(groups, "lxx", module.label, coordinate, metric="active_channel_envelope_enabled_count")


def scan_3xx(module: ModuleData, cell: Cell, coordinate: Coordinate, state: ChannelState, groups: list[ScanGroup]) -> None:
    bucket_metric = "zero_300_count" if cell.effect_param == 0 else "nonzero_3xx_count"
    add_to_groups(groups, "3xx", module.label, coordinate, metric=bucket_metric)
    if cell.effect_param > 0:
        state.tone_portamento_speed = True
    if not state.active_voice:
        add_to_groups(groups, "3xx", module.label, coordinate, metric="no_active_count")
        return
    if module.frequency_table != "linear":
        add_to_groups(groups, "3xx", module.label, coordinate, metric="unsupported_frequency_table_count")
        return
    if is_normal_note(cell.note):
        state.tone_portamento_target = True
    if not state.tone_portamento_target:
        add_to_groups(groups, "3xx", module.label, coordinate, metric="no_target_count")
        return
    if not state.tone_portamento_speed:
        metric = "missing_memory_count" if cell.effect_param == 0 else "no_speed_count"
        add_to_groups(groups, "3xx", module.label, coordinate, metric=metric)
        return
    if cell.effect_param == 0:
        add_to_groups(groups, "3xx", module.label, coordinate, metric="zero_300_memory_reuse_count")
    add_to_groups(groups, "3xx", module.label, coordinate, metric="applied_or_applyable_count")


def scan_axy(module: ModuleData, cell: Cell, coordinate: Coordinate, state: ChannelState, groups: list[ScanGroup]) -> None:
    if cell.effect_param == 0:
        add_to_groups(groups, "axy", module.label, coordinate, metric="a00_count")
        if state.axy_memory is not None:
            add_to_groups(groups, "axy", module.label, coordinate, metric="a00_reuse_if_implemented_count")
        else:
            add_to_groups(groups, "axy", module.label, coordinate, metric="missing_memory_count")
        if not state.active_voice:
            add_to_groups(groups, "axy", module.label, coordinate, metric="no_active_no_op_count")
        else:
            add_to_groups(groups, "axy", module.label, coordinate, metric="active_no_op_count")
        return
    add_to_groups(groups, "axy", module.label, coordinate, metric="nonzero_axy_count")
    up = (cell.effect_param >> 4) & 0x0F
    down = cell.effect_param & 0x0F
    if up > 0 and down > 0:
        add_to_groups(groups, "axy", module.label, coordinate, metric="mixed_nibble_count")
    state.axy_memory = cell.effect_param


def scan_7xy(module: ModuleData, cell: Cell, coordinate: Coordinate, groups: list[ScanGroup]) -> None:
    add_to_groups(groups, "7xy", module.label, coordinate, metric="7xy_count")
    up = (cell.effect_param >> 4) & 0x0F
    down = cell.effect_param & 0x0F
    if cell.effect_param == 0:
        add_to_groups(groups, "7xy", module.label, coordinate, metric="700_count")
    if up == 0 or down == 0:
        add_to_groups(groups, "7xy", module.label, coordinate, metric="zero_nibble_memory_case_count")


def scan_extended_gap(module: ModuleData, cell: Cell, coordinate: Coordinate, groups: list[ScanGroup]) -> None:
    subcommand = (cell.effect_param >> 4) & 0x0F
    amount = cell.effect_param & 0x0F
    if subcommand == 0x00:
        add_to_groups(groups, "e0x", module.label, coordinate, metric="detected_count", family=f"E0{amount:X}")
    elif subcommand == 0x03:
        add_to_groups(groups, "e3x", module.label, coordinate, metric="detected_count", family=f"E3{amount:X}")
        if amount == 0:
            add_to_groups(groups, "e3x", module.label, coordinate, metric="disable_count")
        else:
            add_to_groups(groups, "e3x", module.label, coordinate, metric="enable_or_mode_count")
    elif subcommand == 0x07:
        add_to_groups(groups, "7xy", module.label, coordinate, metric="e7x_control_count", family=f"E7{amount:X}")
    elif subcommand == 0x0E:
        add_to_groups(groups, "eex", module.label, coordinate, metric="detected_count", family=f"EE{amount:X}")


def scan_hxy(module: ModuleData, cell: Cell, coordinate: Coordinate, groups: list[ScanGroup]) -> None:
    add_to_groups(groups, "hxy", module.label, coordinate, metric="detected_count")
    up = (cell.effect_param >> 4) & 0x0F
    down = cell.effect_param & 0x0F
    if cell.effect_param == 0:
        add_to_groups(groups, "hxy", module.label, coordinate, metric="h00_no_op_count")
    else:
        add_to_groups(groups, "hxy", module.label, coordinate, metric="nonzero_hxy_count")
    if up > 0 and down > 0:
        add_to_groups(groups, "hxy", module.label, coordinate, metric="both_nibbles_nonzero_count")


def scan_pxy(module: ModuleData, cell: Cell, coordinate: Coordinate, groups: list[ScanGroup]) -> None:
    add_to_groups(groups, "pxy", module.label, coordinate, metric="detected_count")
    right = (cell.effect_param >> 4) & 0x0F
    left = cell.effect_param & 0x0F
    if cell.effect_param == 0:
        add_to_groups(groups, "pxy", module.label, coordinate, metric="p00_count")
    if right == 0 or left == 0:
        add_to_groups(groups, "pxy", module.label, coordinate, metric="zero_nibble_memory_case_count")


def scan_txy(module: ModuleData, cell: Cell, coordinate: Coordinate, groups: list[ScanGroup]) -> None:
    add_to_groups(groups, "txy", module.label, coordinate, metric="detected_count")
    if cell.effect_param == 0:
        add_to_groups(groups, "txy", module.label, coordinate, metric="t00_memory_case_count")


def scan_rxy(
    module: ModuleData,
    cell: Cell,
    coordinate: Coordinate,
    state: ChannelState,
    speed: int,
    groups: list[ScanGroup],
) -> None:
    add_to_groups(groups, "rxy", module.label, coordinate, metric="detected_count")
    interval = cell.effect_param & 0x0F
    if interval == 0:
        add_to_groups(groups, "rxy", module.label, coordinate, metric="no_op_effect_memory_deferred_count")
    elif interval >= speed:
        add_to_groups(groups, "rxy", module.label, coordinate, metric="out_of_row_no_op_count")
    elif not state.active_voice:
        add_to_groups(groups, "rxy", module.label, coordinate, metric="no_active_count")
    else:
        add_to_groups(groups, "rxy", module.label, coordinate, metric="applied_count")


def scan_kxx(
    module: ModuleData,
    cell: Cell,
    coordinate: Coordinate,
    state: ChannelState,
    speed: int,
    groups: list[ScanGroup],
) -> None:
    add_to_groups(groups, "kxx", module.label, coordinate, metric="detected_count")
    requested_tick = cell.effect_param
    if requested_tick >= speed:
        add_to_groups(groups, "kxx", module.label, coordinate, metric="out_of_row_no_op_count")
    elif not state.active_voice:
        add_to_groups(groups, "kxx", module.label, coordinate, metric="no_active_count")
    else:
        add_to_groups(groups, "kxx", module.label, coordinate, metric="applied_count")


def scan_5xy(module: ModuleData, cell: Cell, coordinate: Coordinate, state: ChannelState, groups: list[ScanGroup]) -> None:
    add_to_groups(groups, "5xy", module.label, coordinate, metric="detected_count")
    if cell.effect_param == 0:
        add_to_groups(groups, "5xy", module.label, coordinate, metric="zero_volume_slide_no_op_count")
    if not state.active_voice:
        add_to_groups(groups, "5xy", module.label, coordinate, metric="no_active_count")
        return
    if module.frequency_table != "linear":
        add_to_groups(groups, "5xy", module.label, coordinate, metric="unsupported_frequency_table_count")
        return
    if is_normal_note(cell.note):
        state.tone_portamento_target = True
    if not state.tone_portamento_target:
        add_to_groups(groups, "5xy", module.label, coordinate, metric="no_target_count")
        return
    if not state.tone_portamento_speed:
        add_to_groups(groups, "5xy", module.label, coordinate, metric="no_speed_count")
        return
    add_to_groups(groups, "5xy", module.label, coordinate, metric="applied_count")


def apply_note_state(module: ModuleData, cell: Cell, state: ChannelState) -> None:
    if cell.instrument > 0:
        state.active_instrument = cell.instrument
    if is_normal_note(cell.note):
        if cell.effect_type not in {0x03, 0x05}:
            state.active_voice = True
            state.tone_portamento_target = False
            state.active_instrument = cell.instrument if cell.instrument > 0 else state.active_instrument
    elif cell.note == 97:
        state.active_voice = state.active_voice


def add_to_groups(
    groups: list[ScanGroup],
    key: str,
    label: str,
    coordinate: Coordinate,
    metric: str = "count",
    *,
    family: str | None = None,
) -> None:
    for group in groups:
        group.bucket(key).add(label, coordinate, metric, family=family)


def load_label_map(path: Path) -> list[dict[str, Any]]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise XMResidualScanError(f"could not read label map: {error.strerror}") from error
    except json.JSONDecodeError as error:
        raise XMResidualScanError(f"malformed label map JSON: line {error.lineno} column {error.colno}") from error
    entries = payload.get("entries") if isinstance(payload, dict) else payload
    if not isinstance(entries, list):
        raise XMResidualScanError("label map must contain an entries array")
    usable = []
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        label = str(entry.get("stable_anonymized_label") or entry.get("label") or "")
        module_path = entry.get("path")
        if not LABEL_RE.match(label) or not isinstance(module_path, str):
            continue
        usable.append({
            "label": label,
            "path": module_path,
            "frequency_table": entry.get("frequency_table"),
        })
    usable.sort(key=lambda item: label_number(item["label"]))
    return usable


def build_scan(label_map_path: Path) -> dict[str, Any]:
    entries = load_label_map(label_map_path)
    groups = {
        "linear": ScanGroup("Linear frequency-table modules"),
        "amiga": ScanGroup("Amiga frequency-table modules"),
        "all": ScanGroup("All modules combined"),
    }
    modules = []
    for entry in entries:
        module = parse_xm_module(Path(entry["path"]), entry["label"], entry.get("frequency_table"))
        modules.append(module)
        target_groups = [groups["all"]]
        if module.frequency_table == "linear":
            target_groups.append(groups["linear"])
        elif module.frequency_table == "amiga":
            target_groups.append(groups["amiga"])
        scan_module(module, target_groups)
    recommendation = recommend_next_pr(groups["linear"])
    return {
        "schema_version": 1,
        "tool": "scripts/summarize-xm-residual-effect-scan.py",
        "local_only": True,
        "generated_at_utc": utc_now(),
        "input_count": len(modules),
        "frequency_table_split": dict(sorted(Counter(module.frequency_table for module in modules).items())),
        "groups": {key: group.to_json() for key, group in groups.items()},
        "recommended_next_implementation_pr": recommendation,
        "privacy": {
            "private_paths_redacted": True,
            "private_filenames_redacted": True,
            "outputs_intended_for_tmp": True,
        },
    }


def recommend_next_pr(linear_group: ScanGroup) -> str:
    pxy = linear_group.bucket("pxy").count("detected_count")
    volume_f = linear_group.bucket("vol_f").count()
    tremolo = linear_group.bucket("7xy").count("7xy_count")
    lxx = linear_group.bucket("lxx").count()

    if lxx > 0:
        return "Minimal Lxx Set Envelope Position"
    if volume_f > 0:
        return "Volume-Column Tone Portamento Foundation"
    if pxy > 0:
        return "Minimal Pxy Panning Slide"
    if tremolo > 0:
        return "Minimal 7xy Tremolo Foundation"
    return "No narrow linear-XM implementation PR from this scan"


def build_markdown_report(scan: dict[str, Any]) -> str:
    split = scan.get("frequency_table_split", {})
    lines = [
        "# Expanded Corpus Residual Effect Memory / Volume Column Scan",
        "",
        "Diagnostics-only local scan. Private module filenames and local paths are redacted; generated artifacts must stay under `/tmp` and out of git.",
        "",
        "## Summary",
        f"- Corpus scanned: {scan.get('input_count', 0)} modules.",
        f"- Linear frequency-table modules: {split.get('linear', 0)}.",
        f"- Amiga frequency-table modules: {split.get('amiga', 0)}.",
        f"- Recommended next implementation PR: **{scan.get('recommended_next_implementation_pr')}**.",
        "- Playback behavior changed: no.",
        "",
    ]
    groups = scan.get("groups", {})
    for key, title in (
        ("linear", "Linear Frequency-Table Modules"),
        ("amiga", "Amiga Frequency-Table Modules"),
        ("all", "All Modules Combined"),
    ):
        lines.extend(group_markdown(title, groups.get(key, {})))
    return "\n".join(lines) + "\n"


def group_markdown(title: str, group: dict[str, Any]) -> list[str]:
    buckets = group.get("buckets", {}) if isinstance(group, dict) else {}
    lines = [
        f"## {title}",
        f"- Modules: {group.get('module_count', 0) if isinstance(group, dict) else 0}",
        "",
        "### Focus Buckets",
        "| Bucket | Count / status | Best target label | First coordinates | Recommendation / status |",
        "| --- | ---: | --- | --- | --- |",
    ]
    lines.append(bucket_line(buckets, "xxy", "A. `Xxy` extra fine portamento", xxy_status))
    lines.append(bucket_line(buckets, "lxx", "B. `Lxx` set envelope position", lxx_status))
    lines.append(bucket_line(buckets, "3xx", "C. `3xx` tone-portamento memory", three_xx_status))
    lines.append(bucket_line(buckets, "axy", "D. `Axy` volume-slide memory", axy_status))
    lines.append(bucket_line(buckets, "7xy", "E. `7xy` tremolo and tremolo memory", tremolo_status))
    lines.append(bucket_line(buckets, "pxy", "F. `Pxy` panning slide", simple_detected_status))
    lines.append(bucket_line(buckets, "e3x", "G. `E3x` glissando control", simple_detected_status))
    lines.append(bucket_line(buckets, "eex", "H. `EEx` pattern delay", simple_detected_status))
    lines.append(bucket_line(buckets, "txy", "I. `Txy` tremor", simple_detected_status))
    lines.append(bucket_line(buckets, "e0x", "J. `E0x` filter toggle", simple_detected_status))
    lines.append(bucket_line(buckets, "vol_a", "K. Volume-column vibrato speed `A0...AF`", volume_a_status))
    lines.append(bucket_line(buckets, "vol_b", "L. Volume-column vibrato depth `B0...BF`", volume_b_status))
    lines.append(bucket_line(buckets, "vol_f", "M. Volume-column tone portamento `F0...FF`", volume_f_status))
    lines.append(bucket_line(buckets, "rxy", "N. `Rxy` residuals", rxy_status))
    lines.append(bucket_line(buckets, "hxy", "O. `Hxy` residuals", hxy_status))
    lines.append(bucket_line(buckets, "kxx", "P. `Kxx` residuals", kxx_status))
    lines.append(bucket_line(buckets, "5xy", "Q. `5xy` residuals", fivexy_status))
    lines.append(bucket_line(buckets, "unknown", "R. Unknown/classification-only high bytes", unknown_status))
    lines.append(bucket_line(buckets, "amiga", "S. Amiga frequency-table residuals", amiga_status))
    lines.extend(["", "### Command Families"])
    for bucket_key in ("xxy", "7xy", "pxy", "e0x", "e3x", "eex", "txy", "vol_a", "vol_b", "vol_f", "unknown", "amiga"):
        bucket = buckets.get(bucket_key, {})
        families = bucket.get("family_counts", {}) if isinstance(bucket, dict) else {}
        if families:
            lines.append(f"- {bucket.get('name', bucket_key)}: {format_counter(families)}")
    lines.append("")
    return lines


def bucket_line(
    buckets: dict[str, Any],
    key: str,
    label: str,
    formatter: Any,
) -> str:
    bucket = buckets.get(key, {})
    if not isinstance(bucket, dict):
        return f"| {label} | 0 | none | none | no occurrences |"
    counts = bucket.get("counts", {}) if isinstance(bucket.get("counts"), dict) else {}
    first = (bucket.get("first_coordinate") or {}).get("text") if isinstance(bucket.get("first_coordinate"), dict) else None
    return (
        f"| {label} | {formatter(counts)} | {bucket.get('best_target_label', 'none')} | "
        f"{first or 'none'} | {status_note(key, counts)} |"
    )


def xxy_status(counts: dict[str, Any]) -> str:
    return str(counts.get("count", 0))


def lxx_status(counts: dict[str, Any]) -> str:
    return (
        f"{counts.get('count', 0)}; envelope evidence "
        f"module={counts.get('module_has_volume_envelope_count', 0)}, "
        f"active={counts.get('active_channel_envelope_enabled_count', 0)}, "
        f"same-cell={counts.get('same_cell_envelope_enabled_count', 0)}"
    )


def three_xx_status(counts: dict[str, Any]) -> str:
    return (
        f"300={counts.get('zero_300_count', 0)}, nonzero={counts.get('nonzero_3xx_count', 0)}, "
        f"300 reuse={counts.get('zero_300_memory_reuse_count', 0)}, "
        f"missing={counts.get('missing_memory_count', 0)}, "
        f"no-active={counts.get('no_active_count', 0)}, no-target={counts.get('no_target_count', 0)}, "
        f"no-speed={counts.get('no_speed_count', 0)}, Amiga/unsupported={counts.get('unsupported_frequency_table_count', 0)}"
    )


def axy_status(counts: dict[str, Any]) -> str:
    return (
        f"A00={counts.get('a00_count', 0)}, nonzero={counts.get('nonzero_axy_count', 0)}, "
        f"A00 reuse-candidates={counts.get('a00_reuse_if_implemented_count', 0)}, "
        f"missing={counts.get('missing_memory_count', 0)}, "
        f"baseline no-active/no-op={counts.get('no_active_no_op_count', 0)}, "
        f"baseline active/no-op={counts.get('active_no_op_count', 0)}, mixed={counts.get('mixed_nibble_count', 0)}"
    )


def tremolo_status(counts: dict[str, Any]) -> str:
    return (
        f"7xy={counts.get('7xy_count', 0)}, 700={counts.get('700_count', 0)}, "
        f"zero-nibble={counts.get('zero_nibble_memory_case_count', 0)}, "
        f"E7x={counts.get('e7x_control_count', 0)}"
    )


def simple_detected_status(counts: dict[str, Any]) -> str:
    return str(counts.get("detected_count", counts.get("count", 0)))


def volume_a_status(counts: dict[str, Any]) -> str:
    return str(counts.get("count", 0))


def volume_b_status(counts: dict[str, Any]) -> str:
    return str(counts.get("count", 0))


def volume_f_status(counts: dict[str, Any]) -> str:
    return str(counts.get("count", 0))


def rxy_status(counts: dict[str, Any]) -> str:
    return (
        f"detected={counts.get('detected_count', 0)}, applied={counts.get('applied_count', 0)}, "
        f"R?0/no-op={counts.get('no_op_effect_memory_deferred_count', 0)}, "
        f"no-active={counts.get('no_active_count', 0)}, out-of-row={counts.get('out_of_row_no_op_count', 0)}"
    )


def hxy_status(counts: dict[str, Any]) -> str:
    return (
        f"detected={counts.get('detected_count', 0)}, H00={counts.get('h00_no_op_count', 0)}, "
        f"nonzero={counts.get('nonzero_hxy_count', 0)}, "
        f"both-nibbles={counts.get('both_nibbles_nonzero_count', 0)}"
    )


def kxx_status(counts: dict[str, Any]) -> str:
    return (
        f"detected={counts.get('detected_count', 0)}, applied={counts.get('applied_count', 0)}, "
        f"no-active={counts.get('no_active_count', 0)}, out-of-row={counts.get('out_of_row_no_op_count', 0)}"
    )


def fivexy_status(counts: dict[str, Any]) -> str:
    return (
        f"detected={counts.get('detected_count', 0)}, applied={counts.get('applied_count', 0)}, "
        f"no-active={counts.get('no_active_count', 0)}, no-target={counts.get('no_target_count', 0)}, "
        f"no-speed={counts.get('no_speed_count', 0)}, "
        f"500 memory-candidates={counts.get('zero_volume_slide_no_op_count', 0)}, "
        f"Amiga/unsupported={counts.get('unsupported_frequency_table_count', 0)}"
    )


def unknown_status(counts: dict[str, Any]) -> str:
    return (
        f"Vxx={counts.get('vxx_count', 0)}, Wxx={counts.get('wxx_count', 0)}, "
        f"other={counts.get('other_high_byte_count', 0)}"
    )


def amiga_status(counts: dict[str, Any]) -> str:
    return (
        f"Amiga 2xx={counts.get('amiga_2xx_count', 0)}, "
        f"Amiga 3xx={counts.get('amiga_3xx_count', 0)}, "
        f"Amiga 5xy={counts.get('amiga_5xy_count', 0)}, "
        f"Amiga Xxy={counts.get('amiga_xxy_count', 0)}, "
        f"Amiga vol-F={counts.get('amiga_volume_column_fxx_count', 0)}"
    )


def status_note(key: str, counts: dict[str, Any]) -> str:
    if key == "xxy":
        return "Supported first-pass; current residuals should be applied/no-active/no-op, not unsupported."
    if key == "lxx":
        return "Deferred; keep after Xxy unless envelope-position evidence dominates."
    if key == "3xx":
        return "Supported first-pass; zero-param memory evidence is classified separately."
    if key == "axy":
        return "Supported first-pass; A00 replay should appear as applied/memory-reused in adapter diagnostics."
    if key == "7xy":
        return "Deferred; E7x control should travel with tremolo if promoted."
    if key == "pxy":
        return "Deferred in the C mixer adapter; legacy Swift panning-slide handler exists."
    if key == "e3x":
        return "Deferred glissando-control state; useful only with portamento parity work."
    if key == "eex":
        return "Deferred traversal/timing hazard."
    if key == "txy":
        return "Deferred tremor effect."
    if key == "e0x":
        return "Deferred limited-use filter toggle."
    if key in {"vol_a", "vol_b"}:
        return "Deferred volume-column vibrato diagnostics only."
    if key == "vol_f":
        return "Deferred volume-column tone portamento diagnostics only."
    if key == "5xy":
        return "Supported first-pass; 500 replay should appear as applied/memory-reused in adapter diagnostics."
    if key in {"rxy", "hxy", "kxx"}:
        return "Supported first-pass; residuals are applied/no-active/no-op/out-of-row classifications."
    if key == "unknown":
        return "Classification-only; no playback work recommended without a concrete target."
    if key == "amiga":
        return "Separate Amiga Frequency Table Foundation bucket."
    return "n/a"


def format_counter(counter: dict[str, Any]) -> str:
    return ", ".join(f"{key}={value}" for key, value in sorted(counter.items(), key=lambda item: (-int(item[1]), item[0])))


TRIAGE_COLUMNS = (
    "key", "target", "docs_keys", "bucket", "metrics", "coverage_commands",
    "legacy_swift", "legacy_evidence", "classic_legacy", "c_mixer_adapter",
    "complexity", "risk", "priority", "docs_correction", "group", "prefer_coverage",
)
TRIAGE_ROWS = [
    ("7xy", "7xy tremolo", ("7xy",), "7xy", ("7xy_count",), ("7xy tremolo",), "yes", "PlaybackEffectHandler.tremolo and applyTremolo", "yes", "no", "medium", "medium", "low unless corpus appears", "no", "all", False),
    ("e7x", "E7x tremolo control", ("E7x",), "7xy", ("e7x_control_count",), ("E7x tremolo control",), "no", "classic handler stores tremolo waveform; Swift legacy path does not expose E7x", "yes", "no", "small with 7xy", "low", "pair with 7xy only", "no", "all", False),
    ("pxy", "Pxy panning slide", ("Pxy",), "pxy", ("detected_count",), ("Pxy panning slide",), "yes", "PlaybackEffectHandler.panningSlide and applyPanningSlide", "yes", "no", "small", "low", "count-driven", "no", "all", False),
    ("3xx", "3xx tone-portamento memory / 300", ("3xx",), "3xx", ("nonzero_3xx_count", "zero_300_count"), ("3xx tone portamento",), "yes", "PlaybackEffectHandler.tonePortamento has zero-param memory support", "yes", "yes", "small docs-only", "low", "docs correction", "yes: replace 'No broad memory claim' with the narrower supported 300 target/speed-memory behavior and residual caveats", "all", True),
    ("5xy", "5xy tone portamento + volume slide memory", ("5xy",), "5xy", ("detected_count",), ("5xy tone portamento + volume slide",), "yes", "combinedTonePortamentoVolumeSlide exists", "yes", "yes", "none", "low", "covered", "no material correction", "all", True),
    ("axy", "Axy volume-slide memory / A00", ("Axy",), "axy", ("a00_count", "nonzero_axy_count"), ("Axy volume slide",), "yes", "PlaybackEffectHandler.volumeSlide has zero-param memory support", "yes", "yes", "none", "low", "covered", "no material correction", "all", True),
    ("rxy", "Rxy multi retrigger / R00", ("Rxy",), "rxy", ("detected_count",), ("Rxy multi retrigger",), "partial", "current adapter implements Rxy; R00 remains no-op", "yes", "yes", "small for R00 only", "medium", "low", "no", "all", True),
    ("hxy", "Hxy global volume slide / H00", ("Hxy",), "hxy", ("detected_count",), ("Hxy global volume slide",), "yes", "PlaybackEffectHandler.globalVolumeSlide exists", "yes", "yes", "none", "low", "covered", "no", "all", True),
    ("vol_a", "Volume-column A0...AF vibrato speed", ("Vibrato speed (A0...AF)",), "vol_a", ("count",), ("volume-column vibrato speed",), "no-op decode only", "decoded in volumeColumnCommand but apply returns false", "yes", "no", "medium", "medium", "low unless corpus appears", "no", "all", False),
    ("vol_b", "Volume-column B0...BF vibrato depth", ("Vibrato depth (B0...BF)",), "vol_b", ("count",), ("volume-column vibrato",), "no-op decode only", "decoded in volumeColumnCommand but apply returns false", "yes", "no", "medium", "medium", "low unless corpus appears", "no", "all", False),
    ("vol_f", "Volume-column F0...FF tone portamento", ("Tone portamento (F0...FF)",), "vol_f", ("count",), ("volume-column tone portamento",), "yes", "PlaybackVolumeColumnCommand.tonePortamento exists in legacy Swift path", "yes", "no", "small", "medium", "high after Lxx if corpus remains small and focused", "no", "all", True),
    ("lxx", "Lxx set envelope position", ("Lxx",), "lxx", ("count",), ("Lxx set envelope position",), "no", "no current Swift adapter envelope-position setter", "yes", "no", "medium", "medium", "high", "no", "all", True),
    ("eex", "EEx pattern delay", ("EEx",), "eex", ("detected_count",), ("EEx pattern delay",), "partial", "PlaybackEffectHandler decodes patternDelay; traversal adapter defers it", "yes", "no", "large", "high", "defer unless corpus appears", "no", "all", False),
    ("txy", "Txy tremor", ("Txy",), "txy", ("detected_count",), ("Txy tremor",), "no", "no current Swift tremor continuous effect", "yes", "no", "medium", "medium", "defer unless corpus appears", "no", "all", False),
    ("e3x", "E3x glissando control", ("E3x",), "e3x", ("detected_count",), ("E3x glissando control",), "no", "no current Swift glissando-control state in C mixer adapter", "yes", "no", "medium", "medium", "defer unless corpus appears", "no", "all", False),
    ("xxy", "X1x/X2x extra fine portamento residuals", ("X1x / X2x",), "xxy", ("count",), ("Xxy extra fine portamento",), "no", "current C mixer adapter owns X1x/X2x support", "yes", "yes", "none", "low", "covered", "no", "all", True),
    ("e0x", "E0x filter toggle", ("E0x",), "e0x", ("detected_count",), ("E0x filter toggle",), "no", "not implemented in current Swift adapter", "yes", "no", "medium", "low", "intentionally deferred", "no", "all", True),
    ("amiga", "Amiga frequency-table 2xx/3xx and portamento cases", ("Amiga frequency table",), "amiga", ("amiga_2xx_count", "amiga_3xx_count", "amiga_5xy_count", "amiga_xxy_count", "amiga_volume_column_fxx_count"), (), "no", "current C mixer adapter is linear-frequency first-pass only", "yes", "no", "large", "high", "separate foundation", "no", "amiga", False),
]
TRIAGE_TARGETS = [
    {
        key: list(value) if key in {"docs_keys", "metrics", "coverage_commands"} else value
        for key, value in zip(TRIAGE_COLUMNS, row)
    }
    for row in TRIAGE_ROWS
]


def normalized_doc_key(value: str) -> str:
    text = re.sub(r"`([^`]*)`", r"\1", value)
    return re.sub(r"\s+", " ", text).strip()


def parse_docs_status(path: Path) -> dict[str, dict[str, str]]:
    if not path.exists():
        return {}
    rows: dict[str, dict[str, str]] = {}
    section = ""
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("## Effect Column Commands"):
            section = "effect"
            continue
        if line.startswith("## Volume Column Commands"):
            section = "volume"
            continue
        if line.startswith("## Frequency Table Support"):
            section = "frequency"
            rows["Amiga frequency table"] = {
                "command": "Amiga frequency table",
                "status": "Deferred separate foundation",
                "effect_memory": "not applicable",
                "runtime_support": "No",
                "offline_support": "No",
                "notes": "Amiga frequency-table pitch behavior is explicitly deferred.",
            }
            continue
        if not section or not line.startswith("|") or "---" in line:
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if section == "effect" and len(cells) >= 7:
            key = normalized_doc_key(cells[0])
            rows[key] = {
                "command": key,
                "name": normalized_doc_key(cells[1]),
                "status": normalized_doc_key(cells[2]),
                "effect_memory": normalized_doc_key(cells[3]),
                "runtime_support": normalized_doc_key(cells[4]),
                "offline_support": normalized_doc_key(cells[5]),
                "notes": normalized_doc_key(cells[6]),
            }
        elif section == "volume" and len(cells) >= 5:
            key = normalized_doc_key(cells[0])
            rows[key] = {
                "command": key,
                "name": key,
                "status": normalized_doc_key(cells[1]),
                "effect_memory": "not applicable",
                "runtime_support": normalized_doc_key(cells[2]),
                "offline_support": normalized_doc_key(cells[3]),
                "notes": normalized_doc_key(cells[4]),
            }
    return rows


def load_coverage_rows(path: Path | None) -> dict[str, dict[str, Any]]:
    if path is None:
        return {}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise XMResidualScanError(f"could not read coverage JSON: {error.strerror}") from error
    except json.JSONDecodeError as error:
        raise XMResidualScanError(f"malformed coverage JSON: line {error.lineno} column {error.colno}") from error
    rows = payload.get("effect_coverage", []) if isinstance(payload, dict) else []
    return {
        str(row.get("command")): row
        for row in rows
        if isinstance(row, dict) and row.get("command") is not None
    }


def docs_summary_for_target(target: dict[str, Any], docs: dict[str, dict[str, str]]) -> dict[str, str]:
    for key in target.get("docs_keys", []):
        if key in docs:
            return docs[key]
    return {
        "command": ", ".join(target.get("docs_keys", [])) or target["target"],
        "status": "not found in docs/xm-effect-support.md",
        "effect_memory": "unknown",
        "runtime_support": "unknown",
        "offline_support": "unknown",
        "notes": "",
    }


def bucket_for_target(scan: dict[str, Any], target: dict[str, Any]) -> dict[str, Any]:
    groups = scan.get("groups", {})
    group = groups.get(target.get("group", "all"), {})
    buckets = group.get("buckets", {}) if isinstance(group, dict) else {}
    bucket = buckets.get(target["bucket"], {})
    return bucket if isinstance(bucket, dict) else {}


def raw_count_for_target(bucket: dict[str, Any], target: dict[str, Any]) -> int:
    counts = bucket.get("counts", {}) if isinstance(bucket.get("counts"), dict) else {}
    return sum(int(counts.get(metric, 0)) for metric in target.get("metrics", ["count"]))


def first_text_for_target(bucket: dict[str, Any], target: dict[str, Any]) -> str:
    first_by_metric = bucket.get("first_by_metric", {}) if isinstance(bucket.get("first_by_metric"), dict) else {}
    for metric in target.get("metrics", ["count"]):
        coord = first_by_metric.get(metric)
        if isinstance(coord, dict) and coord.get("text"):
            return str(coord["text"])
    first = bucket.get("first_coordinate")
    if isinstance(first, dict) and first.get("text"):
        return str(first["text"])
    return "none"


def aggregate_coverage_for_target(target: dict[str, Any], coverage: dict[str, dict[str, Any]]) -> dict[str, Any]:
    rows = [coverage[command] for command in target.get("coverage_commands", []) if command in coverage]
    if not rows:
        return {}
    first = rows[0]
    return {
        "commands": [row.get("command") for row in rows],
        "detected_count": sum(int(row.get("detected_count", 0)) for row in rows),
        "applied_count": sum(int(row.get("applied_count", 0)) for row in rows),
        "deferred_count": sum(int(row.get("deferred_count", 0)) for row in rows),
        "unsupported_count": sum(int(row.get("unsupported_count", 0)) for row in rows),
        "no_op_effect_memory_deferred_count": sum(int(row.get("no_op_effect_memory_deferred_count", 0)) for row in rows),
        "effect_memory_reused_count": sum(int(row.get("effect_memory_reused_count", 0)) for row in rows),
        "effect_memory_missing_count": sum(int(row.get("effect_memory_missing_count", 0)) for row in rows),
        "first_input_label": first.get("first_input_label", "none"),
        "first_coordinate": first.get("first_coordinate", "none"),
        "recommended_implementation_priority": first.get("recommended_implementation_priority", "n/a"),
    }


def adapter_summary(coverage: dict[str, Any], c_mixer_adapter: str) -> str:
    if coverage:
        return (
            f"detected={coverage.get('detected_count', 0)}, applied={coverage.get('applied_count', 0)}, "
            f"deferred={coverage.get('deferred_count', 0)}, unsupported={coverage.get('unsupported_count', 0)}, "
            f"no-op/memory={coverage.get('no_op_effect_memory_deferred_count', 0)}, "
            f"memory reused={coverage.get('effect_memory_reused_count', 0)}, "
            f"memory missing={coverage.get('effect_memory_missing_count', 0)}"
        )
    return "not implemented/reported in current C mixer coverage" if c_mixer_adapter == "no" else "coverage not provided"


def build_gap_triage(scan: dict[str, Any], docs_path: Path, coverage_path: Path | None = None) -> dict[str, Any]:
    docs = parse_docs_status(docs_path)
    coverage_rows = load_coverage_rows(coverage_path)
    targets = []
    for target in TRIAGE_TARGETS:
        bucket = bucket_for_target(scan, target)
        coverage = aggregate_coverage_for_target(target, coverage_rows)
        raw_count = raw_count_for_target(bucket, target)
        raw_counts = bucket.get("counts", {}) if isinstance(bucket.get("counts"), dict) else {}
        corpus_count = coverage.get("detected_count", raw_count) if target.get("prefer_coverage") else raw_count
        best_label = bucket.get("best_target_label") or coverage.get("first_input_label") or "none"
        if best_label == "none" and coverage.get("first_input_label"):
            best_label = coverage["first_input_label"]
        first = first_text_for_target(bucket, target)
        if first == "none" and coverage.get("first_input_label") and coverage.get("first_coordinate"):
            first = f"{coverage['first_input_label']} {coverage['first_coordinate']}"
        targets.append({
            "key": target["key"],
            "target": target["target"],
            "docs": docs_summary_for_target(target, docs),
            "legacy_swift_handler_exists": target["legacy_swift"],
            "legacy_handler_evidence": target["legacy_evidence"],
            "classic_legacy_handler_exists": target["classic_legacy"],
            "c_mixer_adapter_implementation_exists": target["c_mixer_adapter"],
            "current_adapter_coverage": coverage,
            "current_adapter_summary": adapter_summary(coverage, target["c_mixer_adapter"]),
            "raw_counts": raw_counts,
            "raw_corpus_count": raw_count,
            "corpus_count": corpus_count,
            "best_anonymized_target_label": best_label,
            "first_coordinates": first,
            "implementation_complexity": target["complexity"],
            "risk": target["risk"],
            "recommended_priority": target["priority"],
            "docs_correction_needed": target["docs_correction"],
        })
    legacy_doc_mentions = [
        {
            "command": row.get("command", ""),
            "name": row.get("name", ""),
            "status": row.get("status", ""),
            "runtime_support": row.get("runtime_support", ""),
            "offline_support": row.get("offline_support", ""),
            "notes": row.get("notes", ""),
        }
        for row in docs.values()
        if "legacy" in row.get("notes", "").lower()
    ]
    return {
        "schema_version": 1,
        "tool": "scripts/summarize-xm-residual-effect-scan.py --triage-markdown",
        "generated_at_utc": utc_now(),
        "local_only": True,
        "input_count": scan.get("input_count", 0),
        "frequency_table_split": scan.get("frequency_table_split", {}),
        "coverage_json_basename": coverage_path.name if coverage_path else None,
        "privacy": scan.get("privacy", {}),
        "legacy_doc_mentions": legacy_doc_mentions,
        "targets": targets,
        "answers": build_triage_answers(targets, legacy_doc_mentions),
    }


def target_by_key(targets: list[dict[str, Any]], key: str) -> dict[str, Any]:
    return next((target for target in targets if target["key"] == key), {})


def build_triage_answers(targets: list[dict[str, Any]], legacy_doc_mentions: list[dict[str, Any]]) -> dict[str, Any]:
    pxy_count = int(target_by_key(targets, "pxy").get("corpus_count", 0))
    tremolo_count = int(target_by_key(targets, "7xy").get("corpus_count", 0))
    vol_f_count = int(target_by_key(targets, "vol_f").get("corpus_count", 0))
    lxx_count = int(target_by_key(targets, "lxx").get("corpus_count", 0))
    rxy_raw_counts = target_by_key(targets, "rxy").get("raw_counts", {})
    rxy_r00_count = int(rxy_raw_counts.get("no_op_effect_memory_deferred_count", 0)) if isinstance(rxy_raw_counts, dict) else 0
    next_prs = []
    if lxx_count > 0:
        next_prs.append("Minimal Lxx set envelope position foundation")
    if vol_f_count > 0:
        next_prs.append("Volume-column F0...FF tone portamento foundation")
    if pxy_count > 0:
        next_prs.append("Minimal Pxy panning slide")
    if rxy_r00_count > 0:
        next_prs.append("R00 multi-retrigger memory refinement")
    if len(next_prs) < 3:
        next_prs.append("3xx/Axy/5xy memory wording and diagnostics correction, with no playback change")
    if len(next_prs) < 3:
        next_prs.append("Defer 7xy/E7x until corpus evidence appears")
    return {
        "legacy_docs_imply_current_support": "No: legacy-note rows still have Runtime/Offline support marked No, but 3xx memory wording is stale.",
        "surgical_legacy_ports": "Pxy is surgical if corpus evidence exists; 7xy is medium and should carry E7x; volume-column Fxx is a small C mixer adapter port from existing tone-portamento state.",
        "three_xx_memory_gap": "No broad linear 3xx memory gap is indicated; 300 target/speed memory is implemented for active linear voices, with residual no-active/no-target/no-speed caveats.",
        "seven_xy_before_amiga": "No" if tremolo_count == 0 else "Maybe, because corpus evidence exists.",
        "pxy_present": pxy_count > 0,
        "pxy_count": pxy_count,
        "rxy_r00_count": rxy_r00_count,
        "volume_column_tone_portamento_count": vol_f_count,
        "volume_column_tone_portamento_justified": vol_f_count > 0,
        "legacy_doc_mentions": legacy_doc_mentions,
        "recommended_next_three_prs_before_amiga": next_prs[:3],
    }


def build_gap_triage_markdown(triage: dict[str, Any]) -> str:
    split = triage.get("frequency_table_split", {})
    answers = triage.get("answers", {})
    lines = [
        "# Legacy Handler / C Mixer Effect Gap Triage",
        "",
        "Diagnostics-only local audit. Private module filenames and local paths are redacted; generated artifacts must stay under `/tmp` and out of git.",
        "",
        "## Summary",
        f"- Corpus scanned: {triage.get('input_count', 0)} modules ({split.get('linear', 0)} linear, {split.get('amiga', 0)} Amiga).",
        "- Playback behavior changed: no.",
        "- Retired AVAudio backends returned: no.",
        "- Private/local artifacts committed: no.",
        "",
        "## Legacy Docs Mentions",
        "| Command | Docs status | Runtime | Offline | Notes |",
        "| --- | --- | --- | --- | --- |",
    ]
    mentions = triage.get("legacy_doc_mentions", [])
    if mentions:
        for row in mentions:
            lines.append(
                f"| `{row.get('command')}` | {row.get('status')} | {row.get('runtime_support')} | "
                f"{row.get('offline_support')} | {row.get('notes')} |"
            )
    else:
        lines.append("| none | n/a | n/a | n/a | n/a |")
    lines.extend([
        "",
        "## Target Matrix",
        "| Target | Docs status | Legacy Swift handler | C mixer adapter | Corpus count | Best label | First coordinates | Complexity | Risk | Priority | Docs correction |",
        "| --- | --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- |",
    ])
    for target in triage.get("targets", []):
        docs = target.get("docs", {})
        docs_status = (
            f"{docs.get('status', 'unknown')}; runtime {docs.get('runtime_support', 'unknown')}; "
            f"offline {docs.get('offline_support', 'unknown')}"
        )
        lines.append(
            f"| {target.get('target')} | {docs_status} | {target.get('legacy_swift_handler_exists')} | "
            f"{target.get('c_mixer_adapter_implementation_exists')} | {target.get('corpus_count', 0)} | "
            f"{target.get('best_anonymized_target_label')} | {target.get('first_coordinates')} | "
            f"{target.get('implementation_complexity')} | {target.get('risk')} | "
            f"{target.get('recommended_priority')} | {target.get('docs_correction_needed')} |"
        )
    lines.extend([
        "",
        "## Adapter Coverage Notes",
        "| Target | Current adapter summary |",
        "| --- | --- |",
    ])
    for target in triage.get("targets", []):
        lines.append(f"| {target.get('target')} | {target.get('current_adapter_summary')} |")
    lines.extend([
        "",
        "## Questions Answered",
        f"1. Docs entries incorrectly implying legacy support is current support: {answers.get('legacy_docs_imply_current_support')}",
        f"2. Surgical legacy-handler ports: {answers.get('surgical_legacy_ports')}",
        f"3. 3xx memory gap status: {answers.get('three_xx_memory_gap')}",
        f"4. Implement 7xy before Amiga when corpus count is zero: {answers.get('seven_xy_before_amiga')}",
        f"5. Pxy present: {answers.get('pxy_present')} (count {answers.get('pxy_count')}).",
        f"6. Volume-column tone portamento count: {answers.get('volume_column_tone_portamento_count')}; justified: {answers.get('volume_column_tone_portamento_justified')}.",
        f"7. R00 raw memory/deferred count: {answers.get('rxy_r00_count')}. Recommended next three PRs before Amiga:",
    ])
    for index, item in enumerate(answers.get("recommended_next_three_prs_before_amiga", []), start=1):
        lines.append(f"   {index}. {item}.")
    return "\n".join(lines) + "\n"


def write_json(scan: dict[str, Any], path: Path) -> None:
    path.write_text(json.dumps(scan, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label-map", type=Path, default=DEFAULT_LABEL_MAP)
    parser.add_argument("--docs", type=Path, default=DEFAULT_DOCS)
    parser.add_argument("--coverage-json", type=Path, help="Optional redacted C mixer effect coverage JSON to fold into triage")
    parser.add_argument("--json", type=Path, help="Write redacted JSON report")
    parser.add_argument("--markdown", type=Path, help="Write redacted Markdown report")
    parser.add_argument("--triage-json", type=Path, help="Write redacted legacy-handler/C mixer gap triage JSON")
    parser.add_argument("--triage-markdown", type=Path, help="Write redacted legacy-handler/C mixer gap triage Markdown")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        scan = build_scan(args.label_map)
        markdown = build_markdown_report(scan)
        if args.json:
            write_json(scan, args.json)
        if args.markdown:
            args.markdown.write_text(markdown, encoding="utf-8")
        if args.triage_json or args.triage_markdown:
            triage = build_gap_triage(scan, args.docs, args.coverage_json)
            if args.triage_json:
                write_json(triage, args.triage_json)
            if args.triage_markdown:
                args.triage_markdown.write_text(build_gap_triage_markdown(triage), encoding="utf-8")
        if not args.json and not args.markdown:
            if args.triage_json or args.triage_markdown:
                return 0
            print(markdown, end="")
        return 0
    except XMResidualScanError as error:
        print(f"summarize-xm-residual-effect-scan: {error}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

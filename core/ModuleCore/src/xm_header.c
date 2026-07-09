#include "xm_header.h"

#include <stdio.h>
#include <string.h>

static uint16_t read_le_u16(const uint8_t *p) {
    return (uint16_t)(p[0] | ((uint16_t)p[1] << 8));
}

static uint32_t read_le_u32(const uint8_t *p) {
    return (uint32_t)p[0] |
        ((uint32_t)p[1] << 8) |
        ((uint32_t)p[2] << 16) |
        ((uint32_t)p[3] << 24);
}

static size_t min_size(size_t a, size_t b) {
    return a < b ? a : b;
}

static void copy_trimmed(char *dst, size_t dst_size, const uint8_t *src, size_t src_size) {
    size_t count = src_size;
    while (count > 0 && (src[count - 1] == 0 || src[count - 1] == ' ')) {
        count--;
    }
    if (count >= dst_size) {
        count = dst_size - 1;
    }
    memcpy(dst, src, count);
    dst[count] = '\0';
}

static int decode_xm_event(
    const uint8_t *data,
    size_t size,
    size_t *offset,
    uint8_t *note,
    uint8_t *instrument,
    uint8_t *volume,
    uint8_t *effect_type,
    uint8_t *effect_param
) {
    uint8_t b;
    size_t o;

    if (offset == NULL || data == NULL || *offset >= size) {
        return 0;
    }

    o = *offset;
    b = data[o++];

    *note = 0;
    *instrument = 0;
    *volume = 0;
    *effect_type = 0;
    *effect_param = 0;

    if (b & 0x80) {
        if ((b & 0x01) != 0) {
            if (o >= size) { return 0; }
            *note = data[o++];
        }
        if ((b & 0x02) != 0) {
            if (o >= size) { return 0; }
            *instrument = data[o++];
        }
        if ((b & 0x04) != 0) {
            if (o >= size) { return 0; }
            *volume = data[o++];
        }
        if ((b & 0x08) != 0) {
            if (o >= size) { return 0; }
            *effect_type = data[o++];
        }
        if ((b & 0x10) != 0) {
            if (o >= size) { return 0; }
            *effect_param = data[o++];
        }
    } else {
        if (o + 4 > size) {
            return 0;
        }
        *note = b;
        *instrument = data[o++];
        *volume = data[o++];
        *effect_type = data[o++];
        *effect_param = data[o++];
    }

    *offset = o;
    return 1;
}

int mc_parse_xm_header_bytes(const uint8_t *data, size_t size, mc_module_info *out_info) {
    const size_t min_header = 80;
    const size_t fixed_header_fields_size = 20;
    const uint8_t *ptr;
    size_t remaining;
    uint16_t i;
    uint32_t header_size;
    size_t total_header;
    uint16_t version;
    uint16_t song_length;
    uint16_t restart_position;
    uint16_t channels;
    uint16_t patterns;
    uint16_t instruments;
    uint16_t xm_flags;
    uint16_t default_tempo;
    uint16_t default_bpm;
    size_t declared_order_table_length;
    size_t header_order_table_bytes;
    size_t file_order_table_bytes;
    size_t available_order_table_bytes;
    size_t order_table_length;

    if (data == NULL || out_info == NULL) {
        return 0;
    }
    if (size < min_header) {
        return 0;
    }
    if (memcmp(data, "Extended Module: ", 17) != 0) {
        return 0;
    }
    if (data[37] != 0x1A) {
        return 0;
    }

    header_size = read_le_u32(data + 60);
    if (header_size < fixed_header_fields_size) {
        return 0;
    }
    if ((size_t)header_size > SIZE_MAX - 60u) {
        return 0;
    }
    total_header = 60u + (size_t)header_size;
    if (size < total_header) {
        return 0;
    }
    song_length = read_le_u16(data + 64);
    restart_position = read_le_u16(data + 66);
    channels = read_le_u16(data + 68);
    patterns = read_le_u16(data + 70);
    instruments = read_le_u16(data + 72);
    xm_flags = read_le_u16(data + 74);
    default_tempo = read_le_u16(data + 76);
    default_bpm = read_le_u16(data + 78);

    if (channels == 0 || channels > MC_MAX_XM_CHANNELS) {
        return 0;
    }
    if (patterns > MC_MAX_XM_PATTERNS) {
        return 0;
    }

    memset(out_info, 0, sizeof(*out_info));
    out_info->type = MC_MODULE_TYPE_XM;
    copy_trimmed(out_info->title, sizeof(out_info->title), data + 17, 20);

    version = read_le_u16(data + 58);
    out_info->version_major = (uint16_t)((version >> 8) & 0xFF);
    out_info->version_minor = (uint16_t)(version & 0xFF);
    out_info->song_length = song_length;
    out_info->restart_position = restart_position;
    out_info->channels = channels;
    out_info->patterns = patterns;
    out_info->instruments = instruments;
    out_info->xm_flags = xm_flags;
    out_info->default_tempo = default_tempo;
    out_info->default_bpm = default_bpm;

    /*
     * Hostile files can declare a long song but provide a shortened main header.
     * Record only the order bytes actually present before pattern data.
     */
    declared_order_table_length = min_size((size_t)song_length, (size_t)MC_MAX_ORDER_ENTRIES);
    header_order_table_bytes = (size_t)header_size - fixed_header_fields_size;
    file_order_table_bytes = size > min_header ? size - min_header : 0u;
    available_order_table_bytes = min_size(header_order_table_bytes, file_order_table_bytes);
    order_table_length = min_size(declared_order_table_length, available_order_table_bytes);
    out_info->order_table_length = (uint16_t)order_table_length;
    if (order_table_length > 0) {
        memcpy(out_info->order_table, data + min_header, order_table_length);
    }

    ptr = data + total_header;
    remaining = size - total_header;

    out_info->pattern_row_count_count = out_info->patterns;
    if (out_info->pattern_row_count_count > MC_MAX_PATTERN_ROW_COUNTS) {
        out_info->pattern_row_count_count = MC_MAX_PATTERN_ROW_COUNTS;
    }

    for (i = 0; i < out_info->patterns; i++) {
        uint32_t pat_header_len;
        uint16_t row_count;
        uint16_t packed_size;
        const uint8_t *pat_data;
        size_t pat_offset = 0;
        uint16_t row;
        uint16_t ch;

        if (remaining < 9) {
            return 0;
        }
        pat_header_len = read_le_u32(ptr + 0);
        if (pat_header_len < 9 || remaining < pat_header_len) {
            return 0;
        }
        row_count = read_le_u16(ptr + 5);
        packed_size = read_le_u16(ptr + 7);
        if (row_count == 0 || row_count > MC_MAX_XM_PATTERN_ROWS) {
            return 0;
        }
        if (i < out_info->pattern_row_count_count) {
            out_info->pattern_row_counts[i] = row_count;
        }
        if (i < MC_MAX_PATTERN_ROW_COUNTS) {
            out_info->pattern_packed_size_count = i + 1;
            out_info->pattern_packed_sizes[i] = packed_size;
        }
        if ((size_t)packed_size > remaining - (size_t)pat_header_len) {
            return 0;
        }

        pat_data = ptr + pat_header_len;
        for (row = 0; row < row_count; row++) {
            for (ch = 0; ch < out_info->channels; ch++) {
                uint8_t note;
                uint8_t instrument;
                uint8_t volume;
                uint8_t effect_type;
                uint8_t effect_param;

                if (packed_size > 0) {
                    if (!decode_xm_event(
                            pat_data,
                            packed_size,
                            &pat_offset,
                            &note,
                            &instrument,
                            &volume,
                            &effect_type,
                            &effect_param)) {
                        return 0;
                    }
                } else {
                    note = 0;
                    instrument = 0;
                    volume = 0;
                    effect_type = 0;
                    effect_param = 0;
                }

                if (note != 0 || instrument != 0 || volume != 0 || effect_type != 0 || effect_param != 0) {
                    if (out_info->xm_event_count < MC_MAX_XM_EVENTS) {
                        mc_xm_event *event = &out_info->xm_events[out_info->xm_event_count];
                        event->pattern = i;
                        event->row = row;
                        event->channel = ch;
                        event->note = note;
                        event->instrument = instrument;
                        event->volume = volume;
                        event->effect_type = effect_type;
                        event->effect_param = effect_param;
                        out_info->xm_event_count++;
                    } else if (out_info->warning[0] == '\0') {
                        snprintf(
                            out_info->warning,
                            sizeof(out_info->warning),
                            "xm events truncated at %u entries",
                            (unsigned)MC_MAX_XM_EVENTS
                        );
                    }
                }
            }
        }
        if (pat_offset != packed_size) {
            return 0;
        }

        ptr += pat_header_len + packed_size;
        remaining -= pat_header_len + packed_size;
    }

    if (out_info->instruments > 0) {
        uint32_t inst_header_size;
        uint16_t num_samples;

        if (remaining < 29) {
            return 0;
        }
        inst_header_size = read_le_u32(ptr + 0);
        if (inst_header_size < 29 || remaining < inst_header_size) {
            return 0;
        }
        copy_trimmed(out_info->first_instrument_name, sizeof(out_info->first_instrument_name), ptr + 4, 22);
        num_samples = read_le_u16(ptr + 27);

        ptr += inst_header_size;
        remaining -= inst_header_size;

        if (num_samples > 0) {
            /* For now, instrument name only (best effort). Sample/instrument bodies are not parsed yet. */
        }
    }

    out_info->ok = 1;
    return 1;
}

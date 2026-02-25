#include "xm_header.h"

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

int mc_parse_xm_header_bytes(const uint8_t *data, size_t size, mc_module_info *out_info) {
    const size_t min_header = 80;
    const uint8_t *ptr;
    size_t remaining;
    uint16_t i;
    uint32_t header_size;
    size_t total_header;
    uint16_t version;

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
    if (header_size < 20) {
        return 0;
    }
    total_header = 60u + (size_t)header_size;
    if (size < total_header) {
        return 0;
    }

    memset(out_info, 0, sizeof(*out_info));
    out_info->type = MC_MODULE_TYPE_XM;
    out_info->ok = 1;
    copy_trimmed(out_info->title, sizeof(out_info->title), data + 17, 20);

    version = read_le_u16(data + 58);
    out_info->version_major = (uint16_t)((version >> 8) & 0xFF);
    out_info->version_minor = (uint16_t)(version & 0xFF);
    out_info->song_length = read_le_u16(data + 64);
    out_info->restart_position = read_le_u16(data + 66);
    out_info->channels = read_le_u16(data + 68);
    out_info->patterns = read_le_u16(data + 70);
    out_info->instruments = read_le_u16(data + 72);
    out_info->default_tempo = read_le_u16(data + 76);
    out_info->default_bpm = read_le_u16(data + 78);

    out_info->order_table_length = out_info->song_length;
    if (out_info->order_table_length > MC_MAX_ORDER_ENTRIES) {
        out_info->order_table_length = MC_MAX_ORDER_ENTRIES;
    }
    memcpy(out_info->order_table, data + 80, out_info->order_table_length);

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

        if (remaining < 9) {
            return 0;
        }
        pat_header_len = read_le_u32(ptr + 0);
        if (pat_header_len < 9 || remaining < pat_header_len) {
            return 0;
        }
        row_count = read_le_u16(ptr + 5);
        packed_size = read_le_u16(ptr + 7);
        if (i < out_info->pattern_row_count_count) {
            out_info->pattern_row_counts[i] = row_count;
        }
        if (remaining < (size_t)pat_header_len + (size_t)packed_size) {
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

    return 1;
}

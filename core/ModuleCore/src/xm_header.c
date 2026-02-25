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
    out_info->channels = read_le_u16(data + 68);
    out_info->patterns = read_le_u16(data + 70);
    out_info->instruments = read_le_u16(data + 72);

    return 1;
}

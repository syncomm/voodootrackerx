#include "vtx_module_parser.h"

#include <ctype.h>
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

static void zero_info(VTXModuleHeaderInfo *info) {
    memset(info, 0, sizeof(*info));
}

static void copy_trimmed_string(char *dst, size_t dst_size, const uint8_t *src, size_t src_size) {
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

static int is_mod_signature_printable(const uint8_t *sig) {
    for (size_t i = 0; i < 4; i++) {
        if (sig[i] < 32 || sig[i] > 126) {
            return 0;
        }
    }
    return 1;
}

static uint16_t mod_channels_from_signature(const uint8_t *sig) {
    if (memcmp(sig, "M.K.", 4) == 0 ||
        memcmp(sig, "M!K!", 4) == 0 ||
        memcmp(sig, "FLT4", 4) == 0 ||
        memcmp(sig, "4CHN", 4) == 0) {
        return 4;
    }
    if (memcmp(sig, "FLT8", 4) == 0 ||
        memcmp(sig, "8CHN", 4) == 0 ||
        memcmp(sig, "OKTA", 4) == 0 ||
        memcmp(sig, "CD81", 4) == 0) {
        return 8;
    }

    if (isdigit(sig[0]) && isdigit(sig[1]) && sig[2] == 'C' && (sig[3] == 'H' || sig[3] == 'N')) {
        return (uint16_t)((sig[0] - '0') * 10 + (sig[1] - '0'));
    }
    if (isdigit(sig[0]) && sig[1] == 'C' && (sig[2] == 'H' || sig[2] == 'N')) {
        return (uint16_t)(sig[0] - '0');
    }

    return 0;
}

static VTXParseResult parse_xm(const uint8_t *data, size_t size, VTXModuleHeaderInfo *out_info) {
    const size_t base_header_size = 80;
    if (size < base_header_size) {
        return VTX_PARSE_TRUNCATED;
    }
    if (memcmp(data, "Extended Module: ", 17) != 0) {
        return VTX_PARSE_UNSUPPORTED_FORMAT;
    }
    if (data[37] != 0x1A) {
        return VTX_PARSE_INVALID_DATA;
    }

    uint32_t header_size = read_le_u32(data + 60);
    size_t total_header = 60u + (size_t)header_size;
    if (header_size < 20) {
        return VTX_PARSE_INVALID_DATA;
    }
    if (size < total_header) {
        return VTX_PARSE_TRUNCATED;
    }

    zero_info(out_info);
    memcpy(out_info->format, "XM", 3);
    copy_trimmed_string(out_info->title, sizeof(out_info->title), data + 17, 20);

    uint16_t version = read_le_u16(data + 58);
    out_info->version_major = (uint16_t)((version >> 8) & 0xFF);
    out_info->version_minor = (uint16_t)(version & 0xFF);
    out_info->song_length = read_le_u16(data + 64);
    out_info->channels = read_le_u16(data + 68);
    out_info->patterns = read_le_u16(data + 70);
    out_info->instruments = read_le_u16(data + 72);

    return VTX_PARSE_OK;
}

static VTXParseResult parse_mod(const uint8_t *data, size_t size, VTXModuleHeaderInfo *out_info) {
    const size_t mod_header_size = 1084;
    if (size < mod_header_size) {
        return VTX_PARSE_TRUNCATED;
    }

    const uint8_t *sig = data + 1080;
    if (!is_mod_signature_printable(sig)) {
        return VTX_PARSE_UNSUPPORTED_FORMAT;
    }

    zero_info(out_info);
    memcpy(out_info->format, "MOD", 4);
    copy_trimmed_string(out_info->title, sizeof(out_info->title), data, 20);
    out_info->channels = mod_channels_from_signature(sig);
    out_info->song_length = data[950];
    out_info->instruments = 31;

    uint8_t max_pattern = 0;
    size_t entries = out_info->song_length;
    if (entries == 0 || entries > 128) {
        entries = 128;
    }
    for (size_t i = 0; i < entries; i++) {
        uint8_t pattern = data[952 + i];
        if (pattern > max_pattern) {
            max_pattern = pattern;
        }
    }
    out_info->patterns = (entries > 0) ? (uint16_t)(max_pattern + 1) : 0;

    return VTX_PARSE_OK;
}

VTXParseResult vtx_parse_module_header(
    const uint8_t *data,
    size_t size,
    VTXModuleHeaderInfo *out_info
) {
    if (data == NULL || out_info == NULL) {
        return VTX_PARSE_INVALID_ARGUMENT;
    }

    VTXParseResult xm = parse_xm(data, size, out_info);
    if (xm == VTX_PARSE_OK) {
        return xm;
    }
    if (xm == VTX_PARSE_TRUNCATED || xm == VTX_PARSE_INVALID_DATA) {
        return xm;
    }

    return parse_mod(data, size, out_info);
}

const char *vtx_parse_result_string(VTXParseResult result) {
    switch (result) {
    case VTX_PARSE_OK:
        return "ok";
    case VTX_PARSE_INVALID_ARGUMENT:
        return "invalid_argument";
    case VTX_PARSE_UNSUPPORTED_FORMAT:
        return "unsupported_format";
    case VTX_PARSE_TRUNCATED:
        return "truncated";
    case VTX_PARSE_INVALID_DATA:
        return "invalid_data";
    default:
        return "unknown_error";
    }
}

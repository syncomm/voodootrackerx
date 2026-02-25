#include "mod_header.h"

#include <ctype.h>
#include <string.h>

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

static int is_printable_sig(const uint8_t *sig) {
    size_t i;
    for (i = 0; i < 4; i++) {
        if (sig[i] < 32 || sig[i] > 126) {
            return 0;
        }
    }
    return 1;
}

static uint16_t channels_from_sig(const uint8_t *sig) {
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

int mc_parse_mod_header_bytes(const uint8_t *data, size_t size, mc_module_info *out_info) {
    const size_t mod_header_size = 1084;
    const uint8_t *sig;
    uint8_t max_pattern = 0;
    size_t entries;
    size_t i;

    if (data == NULL || out_info == NULL) {
        return 0;
    }
    if (size < mod_header_size) {
        return 0;
    }

    sig = data + 1080;
    if (!is_printable_sig(sig)) {
        return 0;
    }

    memset(out_info, 0, sizeof(*out_info));
    out_info->type = MC_MODULE_TYPE_MOD;
    out_info->ok = 1;
    copy_trimmed(out_info->title, sizeof(out_info->title), data, 20);
    out_info->channels = channels_from_sig(sig);
    out_info->instruments = 31;
    out_info->song_length = data[950];

    entries = out_info->song_length;
    if (entries == 0 || entries > 128) {
        entries = 128;
    }
    for (i = 0; i < entries; i++) {
        uint8_t pattern = data[952 + i];
        if (pattern > max_pattern) {
            max_pattern = pattern;
        }
    }
    out_info->patterns = entries > 0 ? (uint16_t)(max_pattern + 1) : 0;

    return 1;
}

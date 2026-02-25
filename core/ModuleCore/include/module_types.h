#ifndef MC_MODULE_TYPES_H
#define MC_MODULE_TYPES_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    MC_MODULE_TYPE_UNKNOWN = 0,
    MC_MODULE_TYPE_MOD,
    MC_MODULE_TYPE_XM,
} mc_module_type;

enum {
    MC_MAX_ORDER_ENTRIES = 256,
    MC_MAX_PATTERN_ROW_COUNTS = 64,
};

typedef struct {
    char name[23];
    uint32_t length_bytes;
    int8_t finetune;
    uint8_t volume;
} mc_mod_sample_metadata;

typedef struct {
    mc_module_type type;
    int ok;
    char error[128];
    char warning[128];

    char title[21];
    char first_instrument_name[23];

    uint16_t version_major;
    uint16_t version_minor;
    uint16_t channels;
    uint16_t patterns;
    uint16_t instruments;
    uint16_t song_length;
    uint16_t restart_position;
    uint16_t default_tempo;
    uint16_t default_bpm;

    uint16_t order_table_length;
    uint8_t order_table[MC_MAX_ORDER_ENTRIES];

    uint16_t pattern_row_count_count;
    uint16_t pattern_row_counts[MC_MAX_PATTERN_ROW_COUNTS];

    mc_mod_sample_metadata first_mod_sample;
} mc_module_info;

mc_module_info mc_parse_file(const char *path);
const char *mc_module_type_name(mc_module_type type);

#ifdef __cplusplus
}
#endif

#endif

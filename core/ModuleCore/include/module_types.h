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

typedef struct {
    mc_module_type type;
    int ok;
    char error[128];

    char title[21];

    uint16_t version_major;
    uint16_t version_minor;
    uint16_t channels;
    uint16_t patterns;
    uint16_t instruments;
    uint16_t song_length;
} mc_module_info;

mc_module_info mc_parse_file(const char *path);
const char *mc_module_type_name(mc_module_type type);

#ifdef __cplusplus
}
#endif

#endif

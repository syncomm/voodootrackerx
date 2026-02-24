#ifndef VTX_MODULE_PARSER_H
#define VTX_MODULE_PARSER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    VTX_PARSE_OK = 0,
    VTX_PARSE_INVALID_ARGUMENT = 1,
    VTX_PARSE_UNSUPPORTED_FORMAT = 2,
    VTX_PARSE_TRUNCATED = 3,
    VTX_PARSE_INVALID_DATA = 4,
} VTXParseResult;

typedef struct {
    char format[8];
    char title[21];
    uint16_t version_major;
    uint16_t version_minor;
    uint16_t channels;
    uint16_t patterns;
    uint16_t instruments;
    uint16_t song_length;
} VTXModuleHeaderInfo;

VTXParseResult vtx_parse_module_header(
    const uint8_t *data,
    size_t size,
    VTXModuleHeaderInfo *out_info
);

const char *vtx_parse_result_string(VTXParseResult result);

#ifdef __cplusplus
}
#endif

#endif

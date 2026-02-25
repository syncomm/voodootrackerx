#ifndef MC_XM_HEADER_H
#define MC_XM_HEADER_H

#include <stddef.h>
#include <stdint.h>

#include "module_types.h"

int mc_parse_xm_header_bytes(const uint8_t *data, size_t size, mc_module_info *out_info);

#endif

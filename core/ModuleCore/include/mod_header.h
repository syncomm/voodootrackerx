#ifndef MC_MOD_HEADER_H
#define MC_MOD_HEADER_H

#include <stddef.h>
#include <stdint.h>

#include "module_types.h"

int mc_parse_mod_header_bytes(const uint8_t *data, size_t size, mc_module_info *out_info);

#endif

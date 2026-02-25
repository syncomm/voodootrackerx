#include "module_types.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "mod_header.h"
#include "xm_header.h"

static mc_module_info mc_error(const char *message) {
    mc_module_info info;
    memset(&info, 0, sizeof(info));
    info.type = MC_MODULE_TYPE_UNKNOWN;
    info.ok = 0;
    if (message != NULL) {
        snprintf(info.error, sizeof(info.error), "%s", message);
    }
    return info;
}

const char *mc_module_type_name(mc_module_type type) {
    switch (type) {
    case MC_MODULE_TYPE_MOD:
        return "MOD";
    case MC_MODULE_TYPE_XM:
        return "XM";
    case MC_MODULE_TYPE_UNKNOWN:
    default:
        return "UNKNOWN";
    }
}

mc_module_info mc_parse_file(const char *path) {
    FILE *f;
    long file_size;
    uint8_t *data;
    size_t bytes_read;
    mc_module_info info;

    if (path == NULL || path[0] == '\0') {
        return mc_error("invalid path");
    }

    f = fopen(path, "rb");
    if (f == NULL) {
        char msg[128];
        snprintf(msg, sizeof(msg), "open failed: %s", strerror(errno));
        return mc_error(msg);
    }

    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return mc_error("seek failed");
    }
    file_size = ftell(f);
    if (file_size < 0) {
        fclose(f);
        return mc_error("tell failed");
    }
    if (fseek(f, 0, SEEK_SET) != 0) {
        fclose(f);
        return mc_error("seek failed");
    }

    data = (uint8_t *)malloc((size_t)file_size);
    if (data == NULL && file_size > 0) {
        fclose(f);
        return mc_error("out of memory");
    }

    bytes_read = file_size > 0 ? fread(data, 1, (size_t)file_size, f) : 0;
    fclose(f);

    if ((size_t)file_size != bytes_read) {
        free(data);
        return mc_error("read failed");
    }

    if (mc_parse_xm_header_bytes(data, (size_t)file_size, &info)) {
        free(data);
        info.error[0] = '\0';
        return info;
    }

    if (mc_parse_mod_header_bytes(data, (size_t)file_size, &info)) {
        free(data);
        info.error[0] = '\0';
        return info;
    }

    free(data);
    return mc_error("unsupported or invalid module header");
}

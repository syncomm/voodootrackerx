#include <stdio.h>

#include "module_types.h"

int main(int argc, char **argv) {
    mc_module_info info;

    if (argc != 2) {
        fprintf(stderr, "usage: %s <module-file>\n", argv[0]);
        return 2;
    }

    info = mc_parse_file(argv[1]);
    if (!info.ok) {
        fprintf(stderr, "error: %s\n", info.error[0] ? info.error : "unknown error");
        return 1;
    }

    printf("type: %s\n", mc_module_type_name(info.type));
    printf("title: %s\n", info.title);
    if (info.type == MC_MODULE_TYPE_XM) {
        printf("version: %u.%u\n", info.version_major, info.version_minor);
    }
    printf("channels: %u\n", info.channels);
    printf("patterns: %u\n", info.patterns);
    printf("instruments: %u\n", info.instruments);
    printf("song_length: %u\n", info.song_length);

    return 0;
}

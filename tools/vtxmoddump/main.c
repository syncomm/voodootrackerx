#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "vtx_module_parser.h"

static unsigned char *read_file(const char *path, size_t *out_size) {
    FILE *f = fopen(path, "rb");
    if (!f) {
        return NULL;
    }
    if (fseek(f, 0, SEEK_END) != 0) {
        fclose(f);
        return NULL;
    }
    long size = ftell(f);
    if (size < 0) {
        fclose(f);
        return NULL;
    }
    if (fseek(f, 0, SEEK_SET) != 0) {
        fclose(f);
        return NULL;
    }

    unsigned char *buf = (unsigned char *)malloc((size_t)size);
    if (!buf) {
        fclose(f);
        return NULL;
    }

    if (size > 0 && fread(buf, 1, (size_t)size, f) != (size_t)size) {
        free(buf);
        fclose(f);
        return NULL;
    }

    fclose(f);
    *out_size = (size_t)size;
    return buf;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s <module-file>\n", argv[0]);
        return 2;
    }

    size_t size = 0;
    unsigned char *data = read_file(argv[1], &size);
    if (!data) {
        fprintf(stderr, "error: unable to read %s\n", argv[1]);
        return 1;
    }

    VTXModuleHeaderInfo info;
    VTXParseResult result = vtx_parse_module_header(data, size, &info);
    free(data);

    if (result != VTX_PARSE_OK) {
        fprintf(stderr, "parse error: %s\n", vtx_parse_result_string(result));
        return 1;
    }

    printf("format: %s\n", info.format);
    printf("title: %s\n", info.title);
    if (strcmp(info.format, "XM") == 0) {
        printf("version: %u.%u\n", info.version_major, info.version_minor);
    }
    printf("channels: %u\n", info.channels);
    printf("patterns: %u\n", info.patterns);
    printf("instruments: %u\n", info.instruments);
    printf("song_length: %u\n", info.song_length);
    return 0;
}

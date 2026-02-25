#include <stdio.h>
#include <string.h>

#include "module_types.h"

static void print_json_string(const char *s) {
    const unsigned char *p = (const unsigned char *)s;
    putchar('"');
    while (*p) {
        switch (*p) {
        case '\\':
            fputs("\\\\", stdout);
            break;
        case '"':
            fputs("\\\"", stdout);
            break;
        case '\n':
            fputs("\\n", stdout);
            break;
        case '\r':
            fputs("\\r", stdout);
            break;
        case '\t':
            fputs("\\t", stdout);
            break;
        default:
            if (*p < 32) {
                fprintf(stdout, "\\u%04x", *p);
            } else {
                putchar(*p);
            }
            break;
        }
        p++;
    }
    putchar('"');
}

static void print_json(const mc_module_info *info) {
    int i;
    printf("{\n");
    printf("  \"ok\": %s,\n", info->ok ? "true" : "false");
    printf("  \"type\": ");
    print_json_string(mc_module_type_name(info->type));
    printf(",\n");
    printf("  \"error\": ");
    print_json_string(info->error);
    printf(",\n");
    printf("  \"warning\": ");
    print_json_string(info->warning);
    printf(",\n");
    printf("  \"title\": ");
    print_json_string(info->title);
    printf(",\n");
    printf("  \"version\": { \"major\": %u, \"minor\": %u },\n", info->version_major, info->version_minor);
    printf("  \"channels\": %u,\n", info->channels);
    printf("  \"patterns\": %u,\n", info->patterns);
    printf("  \"instruments\": %u,\n", info->instruments);
    printf("  \"song_length\": %u,\n", info->song_length);
    printf("  \"restart_position\": %u,\n", info->restart_position);
    printf("  \"default_tempo\": %u,\n", info->default_tempo);
    printf("  \"default_bpm\": %u,\n", info->default_bpm);
    printf("  \"order_table_length\": %u,\n", info->order_table_length);
    printf("  \"order_table\": [");
    for (i = 0; i < info->order_table_length; i++) {
        if (i > 0) {
            printf(", ");
        }
        printf("%u", info->order_table[i]);
    }
    printf("],\n");
    printf("  \"pattern_row_counts\": [");
    for (i = 0; i < info->pattern_row_count_count; i++) {
        if (i > 0) {
            printf(", ");
        }
        printf("%u", info->pattern_row_counts[i]);
    }
    printf("],\n");
    printf("  \"first_instrument_name\": ");
    print_json_string(info->first_instrument_name);
    printf(",\n");
    printf("  \"first_mod_sample\": {\n");
    printf("    \"name\": ");
    print_json_string(info->first_mod_sample.name);
    printf(",\n");
    printf("    \"length_bytes\": %u,\n", info->first_mod_sample.length_bytes);
    printf("    \"finetune\": %d,\n", info->first_mod_sample.finetune);
    printf("    \"volume\": %u\n", info->first_mod_sample.volume);
    printf("  }\n");
    printf("}\n");
}

int main(int argc, char **argv) {
    mc_module_info info;
    const char *path;
    int json = 0;

    if (argc == 3 && strcmp(argv[1], "--json") == 0) {
        json = 1;
        path = argv[2];
    } else if (argc == 2) {
        path = argv[1];
    } else {
        fprintf(stderr, "usage: %s [--json] <module-file>\n", argv[0]);
        return 2;
    }

    info = mc_parse_file(path);
    if (!info.ok) {
        if (json) {
            print_json(&info);
        } else {
            fprintf(stderr, "error: %s\n", info.error[0] ? info.error : "unknown error");
        }
        return 1;
    }

    if (json) {
        print_json(&info);
        return 0;
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
    printf("restart_position: %u\n", info.restart_position);
    if (info.type == MC_MODULE_TYPE_XM) {
        printf("default_tempo: %u\n", info.default_tempo);
        printf("default_bpm: %u\n", info.default_bpm);
    }
    if (info.warning[0]) {
        printf("warning: %s\n", info.warning);
    }
    if (info.order_table_length > 0) {
        int i;
        printf("order_table:");
        for (i = 0; i < info.order_table_length; i++) {
            printf("%s%u", i == 0 ? " " : ",", info.order_table[i]);
        }
        printf("\n");
    }
    if (info.pattern_row_count_count > 0) {
        int i;
        printf("pattern_row_counts:");
        for (i = 0; i < info.pattern_row_count_count; i++) {
            printf("%s%u", i == 0 ? " " : ",", info.pattern_row_counts[i]);
        }
        printf("\n");
    }
    if (info.first_instrument_name[0]) {
        printf("first_instrument_name: %s\n", info.first_instrument_name);
    }
    if (info.type == MC_MODULE_TYPE_MOD) {
        printf("first_sample_name: %s\n", info.first_mod_sample.name);
        printf("first_sample_length_bytes: %u\n", info.first_mod_sample.length_bytes);
        printf("first_sample_finetune: %d\n", info.first_mod_sample.finetune);
        printf("first_sample_volume: %u\n", info.first_mod_sample.volume);
    }

    return 0;
}

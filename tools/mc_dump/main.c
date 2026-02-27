#include <stdio.h>
#include <stdlib.h>
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

static int should_include_event(const mc_xm_event *event, int include_patterns, int has_pattern_filter, unsigned pattern_filter) {
    if (!include_patterns) {
        return 0;
    }
    if (has_pattern_filter) {
        return event->pattern == pattern_filter;
    }
    return 1;
}

static void print_json(const mc_module_info *info, int include_patterns, int has_pattern_filter, unsigned pattern_filter) {
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
    printf("  \"pattern_packed_sizes\": [");
    for (i = 0; i < info->pattern_packed_size_count; i++) {
        if (i > 0) {
            printf(", ");
        }
        printf("%u", info->pattern_packed_sizes[i]);
    }
    printf("],\n");
    if (include_patterns) {
        int wrote = 0;
        printf("  \"xm_events\": [");
        for (i = 0; i < info->xm_event_count; i++) {
            if (!should_include_event(&info->xm_events[i], include_patterns, has_pattern_filter, pattern_filter)) {
                continue;
            }
            if (wrote) {
                printf(", ");
            }
            printf("{ \"pattern\": %u, \"row\": %u, \"channel\": %u, \"note\": %u, \"instrument\": %u, \"volume\": %u, \"effect_type\": %u, \"effect_param\": %u }",
                info->xm_events[i].pattern,
                info->xm_events[i].row,
                info->xm_events[i].channel,
                info->xm_events[i].note,
                info->xm_events[i].instrument,
                info->xm_events[i].volume,
                info->xm_events[i].effect_type,
                info->xm_events[i].effect_param);
            wrote = 1;
        }
        printf("],\n");
    }
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
    const char *path = NULL;
    int json = 0;
    int include_patterns = 0;
    int has_pattern_filter = 0;
    unsigned pattern_filter = 0;
    int i;

    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--json") == 0) {
            json = 1;
        } else if (strcmp(argv[i], "--include-patterns") == 0) {
            include_patterns = 1;
        } else if (strcmp(argv[i], "--pattern") == 0) {
            char *end = NULL;
            long value;
            if (i + 1 >= argc) {
                fprintf(stderr, "error: --pattern requires an integer argument\n");
                return 2;
            }
            value = strtol(argv[++i], &end, 10);
            if (end == NULL || *end != '\0' || value < 0) {
                fprintf(stderr, "error: invalid pattern index '%s'\n", argv[i]);
                return 2;
            }
            has_pattern_filter = 1;
            include_patterns = 1;
            pattern_filter = (unsigned)value;
        } else if (argv[i][0] == '-') {
            fprintf(stderr, "error: unknown option '%s'\n", argv[i]);
            return 2;
        } else if (path == NULL) {
            path = argv[i];
        } else {
            fprintf(stderr, "error: only one module file path is supported\n");
            return 2;
        }
    }

    if (path == NULL) {
        fprintf(stderr, "usage: %s [--json] [--include-patterns|--pattern N] <module-file>\n", argv[0]);
        return 2;
    }

    info = mc_parse_file(path);
    if (!info.ok) {
        if (json) {
            print_json(&info, include_patterns, has_pattern_filter, pattern_filter);
        } else {
            fprintf(stderr, "error: %s\n", info.error[0] ? info.error : "unknown error");
        }
        return 1;
    }
    if (has_pattern_filter && pattern_filter >= info.patterns) {
        fprintf(stderr, "error: pattern %u out of range (patterns=%u)\n", pattern_filter, info.patterns);
        return 1;
    }

    if (json) {
        print_json(&info, include_patterns, has_pattern_filter, pattern_filter);
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
    if (info.pattern_packed_size_count > 0) {
        int i;
        printf("pattern_packed_sizes:");
        for (i = 0; i < info.pattern_packed_size_count; i++) {
            printf("%s%u", i == 0 ? " " : ",", info.pattern_packed_sizes[i]);
        }
        printf("\n");
    }
    if (include_patterns && info.xm_event_count > 0) {
        int i;
        printf("xm_events:\n");
        for (i = 0; i < info.xm_event_count; i++) {
            if (!should_include_event(&info.xm_events[i], include_patterns, has_pattern_filter, pattern_filter)) {
                continue;
            }
            printf("  p%u r%u c%u: note=%u instrument=%u volume=%u effect=%u param=%u\n",
                info.xm_events[i].pattern,
                info.xm_events[i].row,
                info.xm_events[i].channel,
                info.xm_events[i].note,
                info.xm_events[i].instrument,
                info.xm_events[i].volume,
                info.xm_events[i].effect_type,
                info.xm_events[i].effect_param);
        }
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

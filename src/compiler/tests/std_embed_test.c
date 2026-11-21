#define _POSIX_C_SOURCE 200809L
/* The embedded standard library: the files are the ones build.rs chooses, byte for byte, in order, and
 * they load. Runs from the repository root. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/std_embed.h"
#include "../tools/std_files.h"

static int by_name(const void *a, const void *b) {
    return strcmp(((const MsStdFile *)a)->name, ((const MsStdFile *)b)->name);
}

int main(void) {
    StdFiles disk = {0};
    if (!read_std_files(&disk, "src/stdlib")) {
        return 1;
    }
    qsort(disk.items, disk.count, sizeof *disk.items, by_name);
    uint32_t count = 0;
    const MsStdFile *embedded = ms_std_embedded(&count);
    int failures = 0;
    if (count != disk.count) {
        fprintf(stderr, "embedded %u files, src/stdlib/ has %u\n", count, disk.count);
        failures++;
    }
    for (uint32_t i = 0; i < count && i < disk.count; i++) {
        bool same = strcmp(embedded[i].name, disk.items[i].name) == 0 && embedded[i].len == disk.items[i].len &&
                    memcmp(embedded[i].text, disk.items[i].text, disk.items[i].len) == 0;
        if (!same) {
            fprintf(stderr, "file %u differs: %s\n", i, disk.items[i].name);
            failures++;
        }
    }
    MsNames names;
    ms_names_init(&names);
    MsArena syntax = {0};
    MsCheck check;
    ms_check_init(&check, &names);
    MsStr err = {0};
    if (!ms_std_load(&check, &syntax, embedded, count, &err)) {
        fprintf(stderr, "load: %.*s\n", (int)err.len, err.ptr);
        failures++;
    }
    ms_check_free(&check);
    ms_arena_free(&syntax);
    ms_names_free(&names);
    free_std_files(&disk);
    printf("std_embed_test: %u files, %d failures\n", count, failures);
    return failures == 0 ? 0 : 1;
}

/* The profiler: MS_PROFILE collects samples of a busy thread and writes folded stacks plus a `# dropped` note;
 * MS_PROFILE_ALLOCS samples allocations and writes the count and byte profiles; with nothing set it does nothing. */
#define _POSIX_C_SOURCE 200809L

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "../entry/entry.h"
#include "ms_rt/alloc.h"
#include "ms_rt/sys.h"


static void expect(int condition, const char *what) {
    if (!condition) {
        fprintf(stderr, "entry_profile: failed: %s\n", what);
        exit(1);
    }
}

/* The file's contents, or NULL. */
static char *slurp(const char *path) {
    FILE *file = fopen(path, "rb");
    if (file == NULL) {
        return NULL;
    }
    char *text = calloc(1, 1 << 16);
    if (fread(text, 1, (1 << 16) - 1, file) == 0) {
        text[0] = 0;
    }
    (void)fclose(file);
    return text;
}

static volatile unsigned sink;

static void burn(void) {
    const int64_t start = ms_sys_monotonic_ns();
    while (ms_sys_monotonic_ns() - start < 300000000) {
        for (unsigned i = 0; i < 100000; i++) {
            sink += i;
        }
    }
}

int main(void) {
    char time_path[64];
    char alloc_path[64];
    snprintf(time_path, sizeof time_path, "/tmp/ms-entry-profile-%d.folded", (int)getpid());
    snprintf(alloc_path, sizeof alloc_path, "/tmp/ms-entry-profile-%d.allocs", (int)getpid());

    /* Off by default: nothing is written. */
    unsetenv("MS_PROFILE");
    unsetenv("MS_PROFILE_ALLOCS");
    ms_profile_start();
    ms_profile_attach_runtime_thread();
    ms_profile_finish();
    expect(slurp(time_path) == NULL, "no file without MS_PROFILE");

    setenv("MS_PROFILE", time_path, 1);
    setenv("MS_PROFILE_HZ", "1000", 1);
    setenv("MS_PROFILE_ALLOCS", alloc_path, 1);
    setenv("MS_PROFILE_ALLOC_PERIOD", "4", 1);
    msrt_heap_claim();
    ms_profile_start();
    ms_profile_attach_runtime_thread();
    burn();
    for (int i = 0; i < 100; i++) {
        msrt_free(msrt_alloc(64));
    }
    ms_profile_finish();

    char *folded = slurp(time_path);
    expect(folded != NULL, "the time profile is written");
    expect(strstr(folded, "# dropped 0") != NULL, "the time profile reports dropped samples");
    expect(strstr(folded, "0x") != NULL, "samples of a program without tables are hex addresses");

    char *allocs = slurp(alloc_path);
    expect(allocs != NULL, "the allocation profile is written");
    expect(strstr(allocs, "# period 4") != NULL, "the allocation profile reports its period");
    expect(strstr(allocs, "# allocs") != NULL, "the allocation profile counts allocations");
    char bytes_path[80];
    snprintf(bytes_path, sizeof bytes_path, "%s.bytes", alloc_path);
    char *bytes = slurp(bytes_path);
    expect(bytes != NULL && strstr(bytes, "# bytes") != NULL, "the byte profile is written");

    free(folded);
    free(allocs);
    free(bytes);
    remove(time_path);
    remove(alloc_path);
    remove(bytes_path);
    puts("entry_profile: ok");
    return 0;
}

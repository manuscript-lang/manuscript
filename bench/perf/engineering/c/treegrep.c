#define _GNU_SOURCE
#include <dirent.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

static long files, matches;

static void scan(const char *dir) {
    DIR *d = opendir(dir);
    if (!d) return;
    struct dirent *e;
    while ((e = readdir(d))) {
        if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) continue;
        char path[4096];
        snprintf(path, sizeof path, "%s/%s", dir, e->d_name);
        struct stat st;
        if (stat(path, &st)) continue;
        if (S_ISDIR(st.st_mode)) { scan(path); continue; }
        FILE *f = fopen(path, "rb");
        if (!f) continue;
        char *buf = malloc(st.st_size + 1);
        size_t n = fread(buf, 1, st.st_size, f);
        fclose(f);
        files++;
        char *p = buf, *end = buf + n;
        while (p < end) {
            char *nl = memchr(p, '\n', end - p);
            if (!nl) nl = end;
            if (memmem(p, nl - p, " POST /api/v2/item/17", 21) && memmem(p, nl - p, " 500 ", 5)) matches++;
            p = nl + 1;
        }
        free(buf);
    }
    closedir(d);
}

int main(int argc, char **argv) {
    scan(argv[1]);
    printf("files: %ld\nmatches: %ld\n", files, matches);
    return 0;
}

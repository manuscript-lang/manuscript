#include <dirent.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#define WORKERS 4

static char **files; static size_t nfiles, cap;

static void collect(const char *dir) {
    DIR *d = opendir(dir);
    if (!d) return;
    struct dirent *e;
    while ((e = readdir(d))) {
        if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) continue;
        char path[4096];
        snprintf(path, sizeof path, "%s/%s", dir, e->d_name);
        struct stat st;
        if (stat(path, &st)) continue;
        if (S_ISDIR(st.st_mode)) { collect(path); continue; }
        if (nfiles == cap) files = realloc(files, (cap = cap ? cap * 2 : 64) * sizeof(char *));
        files[nfiles++] = strdup(path);
    }
    closedir(d);
}

typedef struct { long lines, latency, c[4]; size_t first; } Stats;

static void *work(void *arg) {
    Stats *s = arg;
    for (size_t i = s->first; i < nfiles; i += WORKERS) {
        FILE *f = fopen(files[i], "rb");
        if (!f) continue;
        fseek(f, 0, SEEK_END); long size = ftell(f); fseek(f, 0, SEEK_SET);
        char *buf = malloc(size + 1);
        size_t n = fread(buf, 1, size, f);
        fclose(f);
        char *p = buf, *end = buf + n;
        while (p < end) {
            char *nl = memchr(p, '\n', end - p);
            if (!nl) nl = end;
            if (nl > p) {
                char *f5[6]; int k = 0; f5[k++] = p;
                for (char *q = p; q < nl && k < 6; q++) if (*q == ' ') f5[k++] = q + 1;
                s->lines++;
                s->latency += atol(f5[5]);
                int c = f5[4][0] - '2'; if (c < 0 || c > 3) c = 3;
                s->c[c]++;
            }
            p = nl + 1;
        }
        free(buf);
    }
    return NULL;
}

int main(int argc, char **argv) {
    collect(argv[1]);
    pthread_t th[WORKERS]; Stats st[WORKERS] = {0};
    for (int i = 0; i < WORKERS; i++) { st[i].first = i; pthread_create(&th[i], NULL, work, &st[i]); }
    Stats t = {0};
    for (int i = 0; i < WORKERS; i++) {
        pthread_join(th[i], NULL);
        t.lines += st[i].lines; t.latency += st[i].latency;
        for (int c = 0; c < 4; c++) t.c[c] += st[i].c[c];
    }
    printf("files: %zu\nlines: %ld\nstatus: 2xx=%ld 3xx=%ld 4xx=%ld 5xx=%ld\nlatency: %ld\n", nfiles, t.lines, t.c[0], t.c[1], t.c[2], t.c[3], t.latency);
    return 0;
}

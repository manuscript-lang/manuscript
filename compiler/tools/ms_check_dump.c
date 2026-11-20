#define _POSIX_C_SOURCE 200809L
/* ms_check_dump STDLIB_DIR: loads the standard library into the checker tables and prints them in
 * the form crates/ms-check/examples/c_oracle.rs prints, so the two can be diffed. The files are
 * chosen as crates/ms-check/build.rs chooses them: the top-level and one-level-down `.ms` files of the directory, with the
 * files of `stdlib/core/` named flat. */
#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "ms/dump.h"
#include "ms/stdlib.h"

static MsStdFile *files;
static uint32_t nfiles, cap;

static void add_file(const char *dir, const char *rel, const char *name) {
    char path[4096];
    snprintf(path, sizeof path, "%s/%s", dir, rel);
    FILE *f = fopen(path, "rb");
    if (f == NULL) {
        fprintf(stderr, "cannot read %s\n", path);
        exit(1);
    }
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *text = malloc((size_t)n + 1);
    if (fread(text, 1, (size_t)n, f) != (size_t)n) {
        exit(1);
    }
    fclose(f);
    if (nfiles == cap) {
        cap = cap ? cap * 2 : 128;
        files = realloc(files, cap * sizeof *files);
    }
    files[nfiles++] = (MsStdFile){strdup(name), text, (size_t)n};
}

static bool ends_with(const char *s, const char *suffix) {
    size_t a = strlen(s), b = strlen(suffix);
    return a >= b && strcmp(s + a - b, suffix) == 0;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fputs("usage: ms_check_dump STDLIB_DIR\n", stderr);
        return 2;
    }
    const char *root = argv[1];
    DIR *d = opendir(root);
    if (d == NULL) {
        fprintf(stderr, "cannot open %s\n", root);
        return 1;
    }
    for (struct dirent *e; (e = readdir(d)) != NULL;) {
        if (e->d_name[0] == '.') {
            continue;
        }
        char path[4096];
        snprintf(path, sizeof path, "%s/%s", root, e->d_name);
        struct stat st;
        if (stat(path, &st) != 0) {
            continue;
        }
        if (S_ISDIR(st.st_mode)) {
            DIR *sub = opendir(path);
            for (struct dirent *s; sub != NULL && (s = readdir(sub)) != NULL;) {
                if (!ends_with(s->d_name, ".ms")) {
                    continue;
                }
                char rel[4096], name[4096];
                snprintf(rel, sizeof rel, "%s/%s", e->d_name, s->d_name);
                snprintf(name, sizeof name, "%s", strcmp(e->d_name, "core") == 0 ? s->d_name : rel);
                add_file(root, rel, name);
            }
            if (sub != NULL) {
                closedir(sub);
            }
        } else if (ends_with(e->d_name, ".ms")) {
            add_file(root, e->d_name, e->d_name);
        }
    }
    closedir(d);

    MsNames names;
    ms_names_init(&names);
    MsArena syntax = {0};
    MsCheck check;
    ms_check_init(&check, &names);
    MsStr err = {0};
    if (!ms_std_load(&check, &syntax, files, nfiles, &err)) {
        fprintf(stderr, "standard declarations: %.*s\n", (int)err.len, err.ptr);
        return 1;
    }
    MsBuf out = {0};
    ms_dump_std_tables(&out, &check);
    fwrite(out.data, 1, out.len, stdout);
    ms_buf_free(&out);
    ms_check_free(&check);
    ms_arena_free(&syntax);
    ms_names_free(&names);
    return 0;
}

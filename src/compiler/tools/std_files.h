#define _POSIX_C_SOURCE 200809L
/* The standard library's source files, read from a directory as crates/ms-check/build.rs chooses
 * them: the top-level and one-level-down `.ms` files, with the files of `src/stdlib/core/` named flat.
 * For the dump tools of src/compiler/tools; include it from one file. */
#ifndef MS_TOOLS_STD_FILES_H
#define MS_TOOLS_STD_FILES_H

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "ms/stdlib.h"
#include "dump_io.h"
#include "read_file.h"

typedef struct StdFiles {
    MsStdFile *items;
    uint32_t count, cap;
} StdFiles;

static bool add_std_file(StdFiles *files, const char *dir, const char *rel, const char *name) {
    char path[4096];
    snprintf(path, sizeof path, "%s/%s", dir, rel);
    size_t length = 0;
    char *text = read_whole_file(path, &length);
    if (text == NULL) {
        fprintf(stderr, "cannot read %s\n", path);
        return false;
    }
    if (files->count == files->cap) {
        files->cap = files->cap != 0 ? files->cap * 2 : 128;
        files->items = realloc(files->items, files->cap * sizeof *files->items);
    }
    files->items[files->count++] = (MsStdFile){strdup(name), text, length};
    return true;
}

static bool add_std_folder(StdFiles *files, const char *root, const char *folder) {
    char path[4096];
    snprintf(path, sizeof path, "%s/%s", root, folder);
    DIR *sub = opendir(path);
    bool ok = sub != NULL;
    for (struct dirent *s; ok && (s = readdir(sub)) != NULL;) {
        if (!ends_with(s->d_name, ".ms")) {
            continue;
        }
        char rel[4096];
        snprintf(rel, sizeof rel, "%s/%s", folder, s->d_name);
        ok = add_std_file(files, root, rel, strcmp(folder, "core") == 0 ? s->d_name : rel);
    }
    if (sub != NULL) {
        closedir(sub);
    }
    return ok;
}

/* Reads every standard library file under `root`; false (after saying why) on the first failure. */
static bool read_std_files(StdFiles *files, const char *root) {
    DIR *d = opendir(root);
    if (d == NULL) {
        fprintf(stderr, "cannot open %s\n", root);
        return false;
    }
    bool ok = true;
    for (struct dirent *e; ok && (e = readdir(d)) != NULL;) {
        char path[4096];
        struct stat st;
        snprintf(path, sizeof path, "%s/%s", root, e->d_name);
        if (e->d_name[0] == '.' || stat(path, &st) != 0) {
            continue;
        }
        if (S_ISDIR(st.st_mode)) {
            ok = add_std_folder(files, root, e->d_name);
        } else if (ends_with(e->d_name, ".ms")) {
            ok = add_std_file(files, root, e->d_name, e->d_name);
        }
    }
    closedir(d);
    return ok;
}

static void free_std_files(StdFiles *files) {
    for (uint32_t i = 0; i < files->count; i++) {
        /* Both were allocated by add_std_file; MsStdFile only promises not to change them. */
        free((void *)(uintptr_t)files->items[i].name);
        free((void *)(uintptr_t)files->items[i].text);
    }
    free(files->items);
    *files = (StdFiles){0};
}

#endif

/* Reads a whole file into a NUL-terminated heap copy, for the dump tools of src/compiler/tools.
 * NULL when the file cannot be read; free the result. */
#ifndef MS_TOOLS_READ_FILE_H
#define MS_TOOLS_READ_FILE_H

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

static inline char *read_whole_file(const char *path, size_t *length) {
    FILE *f = fopen(path, "rb");
    if (f == NULL) {
        return NULL;
    }
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);
    char *text = malloc((size_t)size + 1);
    bool ok = text != NULL && fread(text, 1, (size_t)size, f) == (size_t)size;
    fclose(f);
    if (!ok) {
        free(text);
        return NULL;
    }
    text[size] = 0;
    *length = (size_t)size;
    return text;
}

#endif

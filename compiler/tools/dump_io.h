/* The line protocol shared by the dump tools of compiler/tools: a request per stdin line, tab-separated
 * fields, answers on stdout. Include it from the tool's one source file. */
#ifndef MS_TOOLS_DUMP_IO_H
#define MS_TOOLS_DUMP_IO_H

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/base.h"

/* Splits `line` at tabs in place; returns the field count (at most `max`). */
static inline size_t split_fields(char *line, char **fields, size_t max) {
    size_t n = 0;
    char *at = line;
    while (n < max) {
        fields[n++] = at;
        char *tab = strchr(at, '\t');
        if (tab == NULL) {
            break;
        }
        *tab = 0;
        at = tab + 1;
    }
    return n;
}

/* Reads one line into `line` without its newline; false at end of input. */
static inline bool read_line(MsBuf *line) {
    line->len = 0;
    char chunk[512];
    while (fgets(chunk, sizeof chunk, stdin) != NULL) {
        size_t n = strlen(chunk);
        bool complete = n > 0 && chunk[n - 1] == '\n';
        ms_buf_put(line, chunk, complete ? n - 1 : n);
        if (complete) {
            break;
        }
    }
    bool any = line->len != 0 || feof(stdin) == 0;
    ms_buf_putc(line, 0);
    return any;
}

static inline MsStr str_of(const char *s) {
    return (MsStr){s, (uint32_t)strlen(s)};
}

static inline size_t number_of(const char *s) {
    return (size_t)strtoul(s, NULL, 10);
}

static inline void put_text(MsStr s) {
    fwrite(s.ptr, 1, s.len, stdout);
}

static inline bool ends_with(const char *s, const char *suffix) {
    size_t a = strlen(s);
    size_t b = strlen(suffix);
    return a >= b && strcmp(s + a - b, suffix) == 0;
}

#endif

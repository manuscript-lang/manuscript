#pragma once
#include <stdio.h>
#include <stdlib.h>
static inline int ms_probe_on(void) {
    static int on = -1;
    if (on < 0) on = getenv("MS_IO_TRACE") != NULL;
    return on;
}
#define MS_PROBE(...) do { if (ms_probe_on()) { fprintf(stderr, "[pr] " __VA_ARGS__); fputc(10, stderr); fflush(stderr); } } while (0)

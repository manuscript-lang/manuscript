/* ms_build_link OBJECT OUT LLD LLC FILES [--strip] [--musl] [--input FILE]...: links OBJECT and the inputs into the
 * executable OUT with the pinned lld (ms/build_link.h). FILES holds crt1.o, crti.o, crtn.o, libc.a, libunwind.a and
 * glibc.symbols. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/build_link.h"

int main(int argc, char **argv) {
    MsLinkOptions options = {0};
    const char *inputs[64];
    size_t ninputs = 0;
    for (int i = 6; i < argc; i++) {
        if (strcmp(argv[i], "--strip") == 0) {
            options.strip = true;
        } else if (strcmp(argv[i], "--musl") == 0) {
            options.musl = true;
        } else if (strcmp(argv[i], "--input") == 0 && i + 1 < argc && ninputs < 64) {
            inputs[ninputs++] = argv[++i];
        } else {
            argc = 0;
        }
    }
    if (argc < 6) {
        fputs("usage: ms_build_link OBJECT OUT LLD LLC FILES [--strip] [--musl] [--input FILE]...\n", stderr);
        return 2;
    }
    options.lld = argv[3];
    options.llc = argv[4];
    options.files = argv[5];
    MsBackendText why = {0};
    if (!ms_build_link(argv[1], inputs, ninputs, argv[2], &options, &why)) {
        fprintf(stderr, "ms_build_link: %.*s\n", (int)why.len, why.ptr == NULL ? "" : why.ptr);
        return 1;
    }
    return 0;
}

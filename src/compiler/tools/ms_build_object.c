/* ms_build_object MIR OUT.o TOOLS [--release] [--no-vectorize] [--keep-ll PATH]: MIR text to an object file with the LLVM
 * tools in directory TOOLS (the C half of `ms build`, ms/build_object.h). Debug unless `--release`. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ms/build_object.h"
#include "read_file.h"

int main(int argc, char **argv) {
    MsObjectOptions options = {.vectorize = true, .backend = {.checks = true}};
    for (int i = 4; i < argc; i++) {
        if (strcmp(argv[i], "--release") == 0) {
            options.backend.speed = true;
        } else if (strcmp(argv[i], "--no-vectorize") == 0) {
            options.vectorize = false;
        } else if (strcmp(argv[i], "--keep-ll") == 0 && i + 1 < argc) {
            options.keep_ll = argv[++i];
        } else {
            argc = 0;
        }
    }
    if (argc < 4) {
        fputs("usage: ms_build_object MIR OUT.o TOOLS [--release] [--no-vectorize] [--keep-ll PATH]\n", stderr);
        return 2;
    }
    options.tools = argv[3];
    size_t len = 0;
    char *mir = read_whole_file(argv[1], &len);
    if (mir == NULL) {
        fprintf(stderr, "ms_build_object: cannot read %s\n", argv[1]);
        return 1;
    }
    MsBackendText object = {0}, why = {0};
    if (!ms_build_object(mir, len, "", 0, &options, &object, &why)) {
        fprintf(stderr, "ms_build_object: %.*s\n", (int)why.len, why.ptr == NULL ? "" : why.ptr);
        return 1;
    }
    FILE *out = fopen(argv[2], "wb");
    if (out == NULL || fwrite(object.ptr, 1, object.len, out) != object.len || fclose(out) != 0) {
        fprintf(stderr, "ms_build_object: cannot write %s\n", argv[2]);
        return 1;
    }
    return 0;
}

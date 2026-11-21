/* `ms build FILE.ms` over libms: the checked program lowered, compiled and linked in C. */
#ifndef MS_BUILD_RUN_H
#define MS_BUILD_RUN_H

#include "ms/base.h"
#include "ms/stdlib.h"

#define MS_BUILD_HANDOVER (-1)

typedef struct MsBuildRequest {
    const char *target;  /* the entry .ms file */
    const char *output;  /* the executable to write */
    const char *runtime; /* the runtime archive linked after the program's object */
    const char *tools;   /* the directory holding `opt` and `llc` */
    const char *lld;     /* the `lld` executable */
    const char *files;   /* the directory with the linker's startup files (ms/build_link.h) */
    bool release;        /* the optimizer at its speed level (build type Release) */
    const char *version; /* the compiler version written to `<output>.ms-build.json` */
    uint8_t tests;       /* 0 builds the program, 1 its `test` blocks under the runner, 2 its `bench` blocks */
    const char *extra;   /* a test build's further sources, one per line */
} MsBuildRequest;

/* Builds `request->target`. Returns 0 when the executable is written, 1 with the reason in `err` when the build
 * failed, or MS_BUILD_HANDOVER with nothing written when the C pipeline cannot give the answer the Rust command would: any
 * diagnostic (Rust renders them), a function the checker or the lowering does not cover, a project the loader does not
 * read. `*handover_reason`, when not NULL, is set to a static text saying why. */
int ms_build_program(const MsStdFile *std_files, uint32_t nstd, const MsBuildRequest *request, MsBuf *err,
                     const char **handover_reason);

#endif

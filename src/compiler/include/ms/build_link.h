/* Linking a program (the Rust `ms-build` link.rs and link/lld.rs): the pinned `lld` joins the object `ms_build_object`
 * wrote with the runtime. On Linux the program links against stand-ins for glibc 2.28's shared libraries, generated
 * from `glibc.symbols` with `llc` and `lld`, so the build machine's glibc is not the program's minimum; with `musl` it
 * links static over musl's startup files. Linux only for now: other hosts return false with a reason, and the Rust
 * `ms` links there. POSIX hosts only. */
#ifndef MS_BUILD_LINK_H
#define MS_BUILD_LINK_H

#include <stdbool.h>
#include <stddef.h>

#include "ms/emit_program.h"

typedef struct MsLinkOptions {
    const char *lld;   /* the `lld` executable */
    const char *llc;   /* the `llc` executable, to generate the glibc stubs */
    const char *files; /* the directory with crt1.o, crti.o, crtn.o, libc.a, libunwind.a and glibc.symbols */
    bool strip;        /* drop the symbol table */
    bool musl;         /* static musl instead of glibc 2.28 stubs; `inputs` must be the musl runtime */
} MsLinkOptions;

/* Links `object` and `inputs` (the runtime archive and `--link` files, in order) into the executable `out`. The glibc
 * stubs are generated into `files/glibc` once. On failure `why` is the reason (freed with ms_backend_free). */
MS_NODISCARD MS_NONNULL bool ms_build_link(const char *object, const char *const *inputs, size_t ninputs, const char *out,
                                           const MsLinkOptions *options, MsBackendText *why);

#endif

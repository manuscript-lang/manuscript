/* MIR text to an object file: the LLVM half of `ms build` (the Rust `c_backend::compile`). The C back end writes
 * LLVM IR (emit_program.h), the pinned `opt` and `llc` compile it, and the fault tables are added to the assembly
 * before it is assembled. POSIX hosts only; the Windows build still goes through the Rust `ms`. */
#ifndef MS_BUILD_OBJECT_H
#define MS_BUILD_OBJECT_H

#include <stdbool.h>

#include "ms/emit_program.h"

typedef struct MsObjectOptions {
    MsBackendOptions backend; /* speed, checks, verify, tables, count_ops, poison_slots */
    const char *tools;        /* the directory holding `opt` and `llc` */
    bool vectorize;           /* LLVM vectorizes loops (`MS_VECTORIZE`) */
    bool llvm_verify;         /* `opt -verify-each` */
    const char *keep_ll;      /* a path the IR is copied to, or NULL */
} MsObjectOptions;

/* Compiles the module `mir` describes (`shown` as for ms_backend_ir) to an object file. On success `object` holds
 * its bytes, freed with ms_backend_free; on failure `why` is the reason, freed with ms_backend_free too. */
MS_NODISCARD MS_NONNULL bool ms_build_object(const char *mir, size_t mir_len, const char *shown, size_t shown_len,
                                             const MsObjectOptions *options, MsBackendText *object, MsBackendText *why);

#endif

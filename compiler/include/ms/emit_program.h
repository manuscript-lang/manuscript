/* The C back end as two calls a host program makes in process (the Rust `ms` links libms and calls
 * them, crates/ms-build/src/c_backend.rs; `ms_mir_build` and `ms_asm_tables` are the same calls as tools):
 *
 *   ms_backend_ir       MIR text of a lowered, elaborated module -> LLVM IR text and the tables meta
 *   ms_backend_tables   the assembly LLVM wrote for that IR -> the assembly with the fault tables
 *   ms_backend_optimized  MIR text -> the optimized MIR text (for `ms emit` with MS_EMIT_OPT=1)
 *
 * Both return true on success. Every text is bytes with a length, not NUL-terminated. A text the call
 * returns is owned by the caller, who frees it with `ms_backend_free`; on failure only `why` is set. */
#ifndef MS_EMIT_PROGRAM_H
#define MS_EMIT_PROGRAM_H
#include <stdbool.h>
#include <stddef.h>

#include "ms_rt/safe.h"

/* Bytes the back end allocated; `ptr` is null when `len` is 0. */
typedef struct MsBackendText {
    char *ptr; /* owned by the caller, freed with ms_backend_free */
    size_t len;
} MsBackendText;

typedef struct MsBackendOptions {
    bool speed;  /* run the optimizer at its speed level */
    bool checks; /* keep the bounds and overflow checks */
    bool verify; /* verify the module after each pass */
    bool tables; /* write source places into the IR and fill `meta`, for ms_backend_tables */
    bool count_ops; /* count executed MIR operations (`ms bench --ops`) */
} MsBackendOptions;

/* Optimizes and finishes the module `mir` describes and writes it as LLVM IR. `name` is what a parse
 * error calls the text. `shown` (`shown_len` bytes, may be empty) holds `printed<TAB>name` lines: a
 * function whose name in the text is `printed` shows `name` in a fault trace (the text form sanitizes a
 * test's name and numbers duplicates). */
MS_NODISCARD MS_NONNULL bool ms_backend_ir(const char *mir, size_t mir_len, const char *name,
                                           const char *shown, size_t shown_len,
                                           const MsBackendOptions *options, MsBackendText *ir,
                                           MsBackendText *meta, MsBackendText *why);

/* The module `mir` describes after the optimizer at its speed level (before the finishing passes and the
 * emitter), as MIR text: what `MS_EMIT_OPT=1 ms emit` prints. */
MS_NODISCARD MS_NONNULL bool ms_backend_optimized(const char *mir, size_t mir_len, const char *name,
                                                  MsBackendText *out, MsBackendText *why);

/* Adds the fault tables to `asm_text`, the assembly of the IR that came with `meta`. `prefix` is what
 * the target puts before a symbol ("_" on Apple, else ""); the `.loc` lines are left out of the result. */
MS_NODISCARD MS_NONNULL bool ms_backend_tables(const char *meta, size_t meta_len, const char *asm_text,
                                               size_t asm_len, const char *prefix, MsBackendText *out,
                                               MsBackendText *why);

/* Frees a text one of the calls above returned and empties it. */
MS_NONNULL void ms_backend_free(MsBackendText *text);

#endif

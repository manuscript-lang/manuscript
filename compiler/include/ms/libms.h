/* libms: the public entry points of the compiler library.
 *
 * Every stage of the pipeline has one entry point here and one slot in the stage table
 * (`ms_stage_impl`). A stage is either implemented in C or still served by the Rust toolchain; the
 * driver (driver.h) runs a command in C only when every stage it needs is in C, and otherwise hands
 * the whole command to the Rust `ms`. Porting a stage means adding its entry point below, writing
 * it in `compiler/src`, and flipping its row in `ms_stage_impl`; no caller changes.
 *
 * No global state: a MsCompiler owns the names and the arena of one compilation. */
#ifndef MS_LIBMS_H
#define MS_LIBMS_H

#include "ms/ast.h"
#include "ms/base.h"

/* ---- stages ---- */

typedef enum MsStage {
    MS_STAGE_PARSE,  /* source text to syntax tree */
    MS_STAGE_FORMAT, /* syntax tree and comments to formatted source */
    MS_STAGE_CHECK,  /* names, types, ownership, effects */
    MS_STAGE_LOWER,  /* checked tree to MIR */
    MS_STAGE_EMIT,   /* MIR to object code (debug: QBE, release: LLVM) */
    MS_STAGE_LINK,   /* objects and runtime archive to an executable */
    MS_STAGE_TOOL,   /* the command's own logic: arguments, reports, project files, servers */
    MS_STAGE_COUNT
} MsStage;

typedef enum MsImpl { MS_IMPL_RUST, MS_IMPL_C } MsImpl;

const char *ms_stage_name(MsStage stage);
/* Where a stage runs today. `MS_STAGES=parse=rust,...` overrides it for comparison runs. */
MsImpl ms_stage_impl(MsStage stage);

/* ---- one compilation ---- */

typedef struct MsCompiler {
    MsArena arena; /* syntax trees, texts, diagnostics */
    MsNames names;
} MsCompiler;

void ms_compiler_init(MsCompiler *c);
void ms_compiler_free(MsCompiler *c); /* frees everything the compilation allocated */

/* A source file read and parsed. Valid until the compiler is freed. */
typedef struct MsSource {
    const char *path;
    const char *text; /* as read, before CRLF normalisation */
    size_t len;
    MsModule module;
} MsSource;

typedef enum MsStatus {
    MS_OK,
    MS_ERR_IO,     /* cannot read the file */
    MS_ERR_UTF8,   /* not valid UTF-8 */
    MS_ERR_SYNTAX  /* *diag holds the first syntax error */
} MsStatus;

/* Parse stage: reads `path` and parses it strictly. On MS_ERR_SYNTAX fills *diag. */
MsStatus ms_load_file(MsCompiler *c, const char *path, MsSource *out, MsDiag *diag);
/* Parses text already in memory (editors, tests). `path` is only recorded. */
MsStatus ms_load_text(MsCompiler *c, const char *path, const char *text, size_t len,
                      MsSource *out, MsDiag *diag);

#endif

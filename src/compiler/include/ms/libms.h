/* libms: the public entry points of the compiler library.
 *
 * Every stage of the pipeline has one entry point here and one slot in the stage table
 * (`ms_stage_table_default`). A stage is either implemented in C or still served by the Rust toolchain; the
 * driver (driver.h) runs a command in C only when every stage it needs is in C, and otherwise hands
 * the whole command to the Rust `ms`. Porting a stage means adding its entry point below, writing
 * it in `src/compiler/src`, and flipping its row in `ms_stage_table_default`; no caller changes.
 *
 * No global state: a MsCompiler owns the names and the arena of one compilation. */
#ifndef MS_LIBMS_H
#define MS_LIBMS_H

#include "ms/ast.h"
#include "ms/base.h"
#include "ms_rt/safe.h"

/* ---- stages ---- */

typedef enum MsStage {
    MS_STAGE_PARSE,  /* source text to syntax tree */
    MS_STAGE_FORMAT, /* syntax tree and comments to formatted source */
    MS_STAGE_CHECK,  /* names, types, ownership, effects */
    MS_STAGE_LOWER,  /* checked tree to MIR */
    MS_STAGE_EMIT,   /* MIR to object code (LLVM) */
    MS_STAGE_LINK,   /* objects and runtime archive to an executable */
    MS_STAGE_TOOL,   /* the command's own logic: arguments, reports, project files, servers */
    MS_STAGE_COUNT
} MsStage;

typedef enum MsImpl { MS_IMPL_RUST, MS_IMPL_C } MsImpl;

const char *ms_stage_name(MsStage stage);

/* Where each stage runs. A value, not a global: the caller owns its table. */
typedef struct MsStageTable {
    MsImpl impl[MS_STAGE_COUNT];
} MsStageTable;

MsStageTable ms_stage_table_default(void);
/* Applies "parse=rust,check=c" (stage=impl, comma separated) over `table`. Returns false and leaves
 * the table untouched when an item names no stage or implementation. */
MS_NODISCARD bool ms_stage_table_override(MsStageTable *table, const char *spec);

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

/* The canonical syntax-tree dump of `text` (src/compiler/tools/ms_syntax_dump `ast`, without the file
 * header), or the one-line "error ..." diagnostic when it does not parse. NULL when the text is
 * not valid UTF-8. Tools read this form; free the result with free(). */
char *ms_syntax_dump_text(const char *path, const char *text, size_t len, size_t *out_len);

#endif

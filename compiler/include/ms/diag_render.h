/* Renders a list of diagnostics the way crates/ms-cli does: the terminal report with a source excerpt
 * under each, and the `--json` document. The renderer owns nothing the caller passes in. */
#ifndef MS_DIAG_RENDER_H
#define MS_DIAG_RENDER_H

#include "ms/base.h"

/* One diagnostic with where it belongs. */
typedef struct MsReport {
    MsDiag diag;
    const char *file;  /* borrowed: the path JSON shows, as the module is named */
    const char *shown; /* borrowed: the path the terminal prints and reads the excerpt from; NULL means `file` */
    const char *phase; /* "parse", "resolution", "type", ... */
} MsReport;

/* Appends the terminal report to `out`: `file:line:column: phase: message`, the excerpt, a line per
 * diagnostic in file, line, column order (ties keep their order), then the count line. */
void ms_render_text(MsBuf *out, const MsReport *items, size_t count);

/* Appends the `{"format": 1, "diagnostics": [...]}` document, indented and newline terminated, in
 * the same order. */
void ms_render_json(MsBuf *out, const MsReport *items, size_t count);

/* The excerpt of one span (a newline, then the gutter, the line and the caret underline), or an empty
 * string when `text` has no such line. `end_line` of 0 means a point diagnostic. Appends to `out`. */
void ms_render_excerpt(MsBuf *out, MsStr text, uint32_t line, uint32_t column, uint32_t end_line,
                       uint32_t end_column);

#endif

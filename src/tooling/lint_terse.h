/* tooling/lint_terse.h: what the two files of the terse rules (MSL118 to MSL135) share. */
#ifndef MS_TOOLING_LINT_TERSE_H
#define MS_TOOLING_LINT_TERSE_H

#include "base/strbuild.h"
#include "compiler/syntax/walk.h"
#include "tooling/lint.h"

typedef struct TerseScan {
  MsArena *arena;
  const MsCheckProgram *program;
  const MsModuleInfo *module;
  MsSpan file;
  MsLintFindingList *findings;
  const uint32_t *mutable_ids; /* the nodes of `var` bindings and parameters, sorted */
  size_t mutable_count;
  MsName enclosing; /* the name of the function being walked, 0 outside one */
} TerseScan;

/* The text of the name `name` is `text`. */
bool terse_name_is(const TerseScan *scan, MsName name, const char *text);

/* `source[from, to)`, or false when the range is not inside the source. */
bool terse_span(const TerseScan *scan, size_t from, size_t to, MsSpan *out);

/* The written text of one balanced expression that fits on a line. */
bool terse_expr_text(const TerseScan *scan, const MsExpr *expr, MsSpan *out);

/* Whether the type of `node` is the builtin `builtin`. */
bool terse_type_is(const TerseScan *scan, MsNode node, MsBuiltin builtin);

/* A finding with no edit. */
void terse_note(const TerseScan *scan, const char *code, MsSpan message, MsPos pos);

/* A finding whose edit replaces source[from, to) with `replacement`. */
void terse_report(const TerseScan *scan, const char *code, MsSpan message, MsPos pos, size_t from, size_t to,
                  MsSpan replacement);

/* `text` copied into the arena. */
MsSpan terse_keep(const TerseScan *scan, MsStrBuild *text);

/* The expression and statement rules, called for every node of the module. */
void terse_expr(const TerseScan *scan, const MsExpr *expr);
void terse_stmt(const TerseScan *scan, const MsStmt *stmt);

#endif

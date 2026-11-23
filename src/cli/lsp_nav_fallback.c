/* cli/lsp_nav_fallback.c: hover on the expressions the occurrence index does not hold (literals and operators), so the
 * cursor on `123`, `+`, `true`, `void`, `[`, `{` or `match` shows the expression's type. Port of Finder::consider in
 * crates/ms-lsp/src/nav.rs. */
#include "cli/lsp_nav_fallback.h"

#include <string.h>

#include "compiler/syntax/walk.h"

typedef struct Finder {
  const MsNames *names;
  size_t offset;
  const MsExpr *best;
  size_t best_len;
} Finder;

static bool text_of(const Finder *f, const MsExpr *e, MsSpan *out) {
  switch ((MsExprKind)e->kind) {
  case MS_E_NUMBER: *out = ms_names_span(f->names, e->u.sym); return true;
  case MS_E_BOOL: *out = ms_span_of_text(e->u.flag ? "true" : "false"); return true;
  case MS_E_VOID: *out = ms_span_of_text("void"); return true;
  case MS_E_LIST: *out = ms_span_of_text("["); return true;
  case MS_E_MAP: *out = ms_span_of_text("{"); return true;
  case MS_E_MATCH: *out = ms_span_of_text("match"); return true;
  case MS_E_UNARY: *out = ms_span_of_text(ms_unary_str((MsUnaryOp)e->op)); return true;
  case MS_E_BINARY: *out = ms_span_of_text(ms_binary_str((MsBinaryOp)e->op)); return true;
  default: return false;
  }
}

static void consider(void *ctx, const MsExpr *e) {
  Finder *f = ctx;
  MsSpan text;
  if (!text_of(f, e, &text) || text.len == 0) return;
  if (f->offset < e->pos.offset || f->offset >= e->pos.offset + text.len) return;
  if (f->best == NULL || text.len < f->best_len) {
    f->best = e;
    f->best_len = text.len;
  }
}

bool lsp_hover_fallback(const MsNames *names, const MsModule *tree, size_t offset, LspHoverFallback *out) {
  Finder finder = {names, offset, NULL, 0};
  const MsVisitor visitor = {.ctx = &finder, .expr = consider};
  for (uint32_t i = 0; i < tree->ndecls; i++) ms_walk_decl(&visitor, tree->decls[i]);
  if (finder.best == NULL) return false;
  MsSpan text;
  (void)text_of(&finder, finder.best, &text);
  out->node = finder.best->id;
  out->expr = finder.best;
  out->text = text;
  out->offset = finder.best->pos.offset;
  out->end = finder.best->pos.offset + text.len;
  return true;
}

bool lsp_match_never(const MsExpr *expr) {
  if (expr->kind != MS_E_MATCH || expr->u.match.arms.len == 0) return false;
  for (uint32_t i = 0; i < expr->u.match.arms.len; i++) {
    const MsArm *arm = expr->u.match.arms.ptr[i];
    if (arm->value != NULL || arm->body.len == 0) return false;
    const MsStmt *last = arm->body.ptr[arm->body.len - 1];
    if (last->kind != MS_S_RETURN && last->kind != MS_S_BREAK && last->kind != MS_S_CONTINUE) return false;
  }
  return true;
}

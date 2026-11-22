/* Owns drop_labels.h: finds the labels the call facts show to be redundant and cuts them from the source. */
#include "compiler/check/drop_labels.h"

#include "base/list.h"
#include "base/sort.h"
#include "base/strbuild.h"
#include "compiler/syntax/walk.h"

enum { MAX_PARAMS = 64 };

typedef struct Cut {
  size_t from, to;
} Cut;

MS_LIST_DEFINE(CutList, cut_list, Cut)

typedef struct Scan {
  const MsCheckProgram *program;
  const MsFacts *facts;
  MsSpan source;
  CutList cuts;
} Scan;

static int64_t cut_order(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const Cut *x = (const void *)a;
  const Cut *y = (const void *)b;
  return x->from == y->from ? 0 : (x->from < y->from ? -1 : 1);
}

/* Cuts the label `name` and its colon from the gap [from, to) that precedes the argument's value. A gap with
 * comments keeps them: only the name, and the colon with the blanks after it, go. */
static void drop_label(Scan *scan, size_t from, size_t to, size_t name_len) {
  const MsSpan gap = ms_span_of(scan->source.ptr + from, to - from);
  bool commented = false;
  for (size_t i = 0; i + 1 < gap.len; i++) {
    commented = commented || (gap.ptr[i] == '/' && (gap.ptr[i + 1] == '/' || gap.ptr[i + 1] == '*'));
  }
  if (!commented) {
    cut_list_push(&scan->cuts, (Cut){from, to});
    return;
  }
  size_t colon = name_len;
  while (colon < gap.len && gap.ptr[colon] != ':') {
    if (gap.ptr[colon] == '/' && colon + 1 < gap.len && gap.ptr[colon + 1] == '/') {
      while (colon < gap.len && gap.ptr[colon] != '\n') {
        colon++;
      }
    } else if (gap.ptr[colon] == '/' && colon + 1 < gap.len && gap.ptr[colon + 1] == '*') {
      colon += 2;
      while (colon + 1 < gap.len && !(gap.ptr[colon] == '*' && gap.ptr[colon + 1] == '/')) {
        colon++;
      }
      colon += 2;
    } else {
      colon++;
    }
  }
  if (colon >= gap.len) {
    return;
  }
  size_t spaces = colon + 1;
  while (spaces < gap.len && (gap.ptr[spaces] == ' ' || gap.ptr[spaces] == '\t')) {
    spaces++;
  }
  cut_list_push(&scan->cuts, (Cut){from, from + name_len});
  cut_list_push(&scan->cuts, (Cut){from + colon, from + spaces});
}

/* The parameter of `call` that the written expression `node` fills, or -1. */
static int parameter_of(const MsCall *call, MsNode node) {
  for (uint32_t p = 0; p < call->arg_count; p++) {
    if (call->args[p].source == MS_ARG_WRITTEN && call->args[p].node.node == node) {
      return (int)p;
    }
  }
  return -1;
}

static void scan_call(Scan *scan, const MsExpr *expr, const MsCall *call) {
  bool supplied[MAX_PARAMS] = {false};
  for (uint32_t p = 0; p < call->arg_count; p++) {
    bool written_here = false;
    for (uint32_t a = 0; a < expr->u.call.args.len; a++) {
      written_here = written_here || call->args[p].node.node == expr->u.call.args.ptr[a].value->id;
    }
    supplied[p] = call->args[p].source == MS_ARG_WRITTEN && !written_here; /* the receiver of a method */
  }
  for (uint32_t a = 0; a < expr->u.call.args.len; a++) {
    const MsArg *arg = &expr->u.call.args.ptr[a];
    const int p = parameter_of(call, arg->value->id);
    if (p < 0) {
      continue;
    }
    uint32_t first = 0;
    while (first < call->arg_count && supplied[first]) {
      first++;
    }
    const MsSpan label = arg->has_name ? ms_names_span(scan->program->names, arg->name) : (MsSpan){0};
    if (arg->has_name && first == (uint32_t)p && arg->value->kind == MS_E_NAME && arg->value->u.sym == arg->name &&
        arg->pos.offset < arg->value->pos.offset && arg->value->pos.offset <= scan->source.len) {
      drop_label(scan, arg->pos.offset, arg->value->pos.offset, label.len);
    }
    supplied[p] = true;
  }
}

static void on_expr(void *ctx, const MsExpr *expr) {
  Scan *scan = ctx;
  if (expr->kind != MS_E_CALL) {
    return;
  }
  const MsCall *call = ms_facts_call(scan->facts, expr->id);
  if (call == NULL || call->callee.kind == MS_REF_CASE || call->arg_count > MAX_PARAMS) {
    return;
  }
  scan_call(scan, expr, call);
}

MsSpan ms_drop_redundant_labels(MsArena *arena, const MsCheckProgram *program, uint32_t module, MsSpan source) {
  const MsModuleInfo *info = &program->modules.ptr[module];
  Scan scan = {.program = program, .facts = &info->facts, .source = source};
  const MsVisitor visitor = {.ctx = &scan, .expr = on_expr};
  for (uint32_t i = 0; i < info->tree->ndecls; i++) {
    ms_walk_decl(&visitor, info->tree->decls[i]);
  }
  if (scan.cuts.len == 0) {
    cut_list_free(&scan.cuts);
    return source;
  }
  ms_sort((uint8_t *)scan.cuts.ptr, scan.cuts.len, sizeof(Cut), cut_order, NULL);
  MsStrBuild edited = ms_strbuild_new();
  size_t cursor = 0;
  for (size_t i = 0; i < scan.cuts.len; i++) {
    ms_strbuild_append(&edited, ms_span_of(source.ptr + cursor, scan.cuts.ptr[i].from - cursor));
    cursor = scan.cuts.ptr[i].to;
  }
  ms_strbuild_append(&edited, ms_span_of(source.ptr + cursor, source.len - cursor));
  const MsSpan result = ms_arena_copy(arena, ms_strbuild_span(&edited));
  ms_strbuild_free(&edited);
  cut_list_free(&scan.cuts);
  return result;
}

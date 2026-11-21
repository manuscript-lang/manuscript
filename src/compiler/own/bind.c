/* compiler/own/bind.c: reading bindings out of the checker's facts. */
#include "compiler/own/bind.h"
#include "compiler/syntax/walk.h"

bool ms_bind_of(const MsFacts *facts, MsNode node, uint32_t *binding) {
  const MsRef *ref = ms_facts_ref(facts, node);
  if (ref == NULL || (ref->kind != MS_REF_LOCAL && ref->kind != MS_REF_PARAM)) {
    return false;
  }
  *binding = ref->decl.node;
  return true;
}

bool ms_bind_field_chain(const MsFacts *facts, MsArena *arena, const MsExpr *expr, const MsExpr **root,
                         uint32_t *binding, MsLivePath *path) {
  uint32_t depth = 0;
  const MsExpr *at = expr;
  while (at->kind == MS_E_MEMBER) {
    depth++;
    at = at->u.member.left;
  }
  if (depth == 0 || at->kind != MS_E_NAME || !ms_bind_of(facts, at->id, binding)) {
    return false;
  }
  MsName *names = MS_ARENA_NEW_ARRAY(arena, MsName, depth);
  at = expr;
  for (uint32_t index = depth; index > 0; index--) {
    names[index - 1] = at->u.member.name;
    at = at->u.member.left;
  }
  *root = at;
  *path = (MsLivePath){.names = names, .len = depth};
  return true;
}

/* The node ids a lambda's own syntax spans, and the bindings it names, collected in one walk. */
typedef struct CaptureScan {
  const MsFacts *facts;
  MsNode low, high;
  MsBindingList used;
} CaptureScan;

static void note_node(CaptureScan *scan, MsNode node) {
  if (node < scan->low) {
    scan->low = node;
  }
  if (node > scan->high) {
    scan->high = node;
  }
}

static void note_pattern(CaptureScan *scan, const MsPattern *pattern) {
  note_node(scan, pattern->id);
  if (pattern->kind == MS_P_LIST) {
    for (uint32_t index = 0; index < pattern->u.list.len; index++) {
      note_pattern(scan, pattern->u.list.ptr[index]);
    }
  } else if (pattern->kind == MS_P_TYPE) {
    for (uint32_t index = 0; index < pattern->u.fields.len; index++) {
      note_pattern(scan, pattern->u.fields.ptr[index].pattern);
    }
  }
}

static void scan_stmt(void *context, const MsStmt *stmt) {
  CaptureScan *scan = context;
  note_node(scan, stmt->id);
  if (stmt->kind == MS_S_BIND) {
    note_pattern(scan, stmt->u.bind.pattern);
  } else if (stmt->kind == MS_S_IF && stmt->u.branch.binding != NULL) {
    note_pattern(scan, stmt->u.branch.binding);
  }
}

static void scan_expr(void *context, const MsExpr *expr) {
  CaptureScan *scan = context;
  note_node(scan, expr->id);
  if (expr->kind == MS_E_LAMBDA) {
    for (uint32_t index = 0; index < expr->u.lambda.params.len; index++) {
      note_node(scan, expr->u.lambda.params.ptr[index]->id);
    }
  } else if (expr->kind == MS_E_MATCH) {
    for (uint32_t index = 0; index < expr->u.match.arms.len; index++) {
      note_node(scan, expr->u.match.arms.ptr[index]->id);
    }
  } else if (expr->kind == MS_E_NAME) {
    uint32_t binding = 0;
    if (ms_bind_of(scan->facts, expr->id, &binding)) {
      ms_binding_list_push(&scan->used, binding);
    }
  }
}

static bool listed(const MsBindingList *list, uint32_t binding) {
  for (size_t index = 0; index < list->len; index++) {
    if (list->ptr[index] == binding) {
      return true;
    }
  }
  return false;
}

MsBindingList ms_bind_captures(const MsFacts *facts, const MsExpr *lambda) {
  CaptureScan scan = {.facts = facts, .low = UINT32_MAX, .high = 0};
  const MsVisitor visitor = {.ctx = &scan, .stmt = scan_stmt, .expr = scan_expr};
  ms_walk_expr(&visitor, lambda);
  MsBindingList captures = {0};
  for (size_t index = 0; index < scan.used.len; index++) {
    const uint32_t binding = scan.used.ptr[index];
    const bool inside = binding >= scan.low && binding <= scan.high;
    if (!inside && !listed(&captures, binding)) {
      ms_binding_list_push(&captures, binding);
    }
  }
  ms_binding_list_free(&scan.used);
  return captures;
}

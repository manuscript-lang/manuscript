/* compiler/check/narrow.c: flow narrowing of a nullable local. After `if v != null:`, in the rest of a block that
 * follows `if v == null: return`, and on the right of `v != null and ...` or `v == null or ...`, an immutable local or
 * parameter `v` of type `T?` reads as `T`. The use is typed `T`, its node keeps the stored type `T?` and carries a
 * MS_CONV_NARROW conversion, so lowering yields the payload of the same value. */
#include "compiler/check/body.h"
#include "compiler/syntax/walk.h"

static bool is_nullable_type(const Body *body, MsTy ty) {
  const MsTyTable *types = &body->program->types;
  return ty != MS_TY_NONE && ms_ty_is(types, ty, MS_BUILTIN_Optional) && ms_ty_arg_count(types, ty) == 1;
}

static bool is_null_name(const Body *body, const MsExpr *expr) {
  return expr->kind == MS_E_NAME && body_find_local(body, expr->u.sym) == NULL &&
         ms_span_is_text(ms_names_span(body->program->names, expr->u.sym), "null");
}

size_t body_narrow_mark(const Body *body) {
  return body->narrow_len;
}

void body_narrow_reset(Body *body, size_t mark) {
  while (body->narrow_len > mark) {
    const BodyNarrow *entry = &body->narrowed[--body->narrow_len];
    body->locals.ptr[entry->local].narrowed = entry->previous;
  }
}

/* Narrows the local `name` when it is an immutable nullable that is not narrowed yet. */
static void narrow_local(Body *body, const MsExpr *name) {
  const MsLocal *found = body_find_local(body, name->u.sym);
  if (found == NULL || found->is_var || found->rejected || found->narrowed != MS_TY_NONE ||
      !is_nullable_type(body, found->ty) || body->narrow_len >= MS_NARROW_MAX) {
    return;
  }
  const size_t index = (size_t)(found - body->locals.ptr);
  body->narrowed[body->narrow_len++] = (BodyNarrow){.local = index, .previous = found->narrowed};
  body->locals.ptr[index].narrowed = ms_ty_args(&body->program->types, found->ty)[0];
}

/* Narrows what `cond` being `truth` tells: `v != null` true and `v == null` false, through `and` (true), `or` (false)
 * and `not`. */
void body_narrow(Body *body, const MsExpr *cond, bool truth) {
  if (cond->kind == MS_E_UNARY && cond->op == MS_U_NOT) {
    body_narrow(body, cond->u.bin.left, !truth);
    return;
  }
  if (cond->kind != MS_E_BINARY) {
    return;
  }
  const MsBinaryOp op = (MsBinaryOp)cond->op;
  if ((op == MS_B_AND && truth) || (op == MS_B_OR && !truth)) {
    body_narrow(body, cond->u.bin.left, truth);
    body_narrow(body, cond->u.bin.right, truth);
    return;
  }
  if (op != MS_B_EQ && op != MS_B_NE) {
    return;
  }
  const bool present = truth == (op == MS_B_NE);
  const MsExpr *left = cond->u.bin.left;
  const MsExpr *right = cond->u.bin.right;
  const MsExpr *name = is_null_name(body, right) ? left : is_null_name(body, left) ? right : NULL;
  if (present && name != NULL && name->kind == MS_E_NAME) {
    narrow_local(body, name);
  }
}

/* Whether control cannot leave `stmts` at their end: a return, break, continue, a call that never returns, or an
 * `if` whose branches both do not. */
bool body_block_exits(const Body *body, MsStmts stmts) {
  if (stmts.len == 0) {
    return false;
  }
  const MsStmt *last = stmts.ptr[stmts.len - 1];
  switch ((MsStmtKind)last->kind) {
  case MS_S_RETURN:
  case MS_S_BREAK:
  case MS_S_CONTINUE:
    return true;
  case MS_S_CALL:
    return last->u.expr != NULL &&
           ms_ty_is(&body->program->types, ms_facts_type(body->facts, last->u.expr->id), MS_BUILTIN_Never);
  case MS_S_IF:
    return last->u.branch.binding == NULL && last->u.branch.else_body.len != 0 &&
           body_block_exits(body, last->u.branch.body) && body_block_exits(body, last->u.branch.else_body);
  case MS_S_BIND:
  case MS_S_ASSIGN:
  case MS_S_WHILE:
  case MS_S_FOR:
    break;
  }
  return false;
}

/* Records that the use `expr` of a narrowed local is stored as `T?` and read as `T`. */
void body_note_narrowing(Body *body, const MsExpr *expr, MsTy read) {
  const MsLocal *local = body_find_local(body, expr->u.sym);
  if (local == NULL || local->narrowed == MS_TY_NONE || local->narrowed != read) {
    return;
  }
  body_set_type(body, expr->id, local->ty);
  for (size_t at = body->facts->conversions.len, seen = 0; at > 0 && seen < 8; at--, seen++) {
    const MsConversion *earlier = &body->facts->conversions.ptr[at - 1];
    if (earlier->node == expr->id && earlier->kind == MS_CONV_NARROW) {
      return;
    }
  }
  const MsConversion conversion = {expr->id, MS_CONV_NARROW, local->ty, read};
  ms_facts_add_conversion(body->facts, &conversion);
}

/* compiler/own/live_expr.c: the expression half of the liveness walk, children in reverse evaluation order. */
#include "compiler/own/live_pass.h"
#include "compiler/syntax/parse.h"

static const MsLivePath no_path = {0};

void ms_live_record(MsLivePass *pass, MsNode node, MsNode place_node, uint32_t binding, MsLivePath path,
                    MsLiveSet *live) {
  const MsNode next = ms_live_next_use(live, binding, no_path);
  ms_live_map_put(&pass->out->uses, ms_live_key(node, binding), (MsUseLive){.next = next, .last = next == MS_NO_NODE});
  const MsNode near = ms_live_next_use(live, binding, path);
  ms_live_map_put(&pass->out->places, ms_live_key(place_node, binding),
                  (MsUseLive){.next = near, .last = near == MS_NO_NODE});
  ms_live_insert(live, binding, path, node);
}

/* A name or a chain of member reads on one. */
static bool is_place(const MsExpr *expr) {
  while (expr->kind == MS_E_MEMBER) {
    expr = expr->u.member.left;
  }
  return expr->kind == MS_E_NAME;
}

/* `place[key] = value` whose key is a place: the parser writes it as a call of `[]=`, and the key is consumed
 * at the store, after the value ran. */
static bool is_index_store(const MsNames *names, const MsExpr *call) {
  const MsExpr *callee = call->u.call.callee;
  return call->u.call.args.len == 2 && callee->kind == MS_E_MEMBER &&
         ms_span_is_text(ms_names_span(names, callee->u.member.name), MS_INDEX_SET) &&
         is_place(call->u.call.args.ptr[0].value);
}

static void walk_text(MsLivePass *pass, const MsExpr *expr, MsLiveSet *live) {
  for (uint32_t index = expr->u.text.len; index > 0; index--) {
    const MsExpr *part = expr->u.text.ptr[index - 1].expr;
    if (part != NULL) {
      ms_live_expr(pass, part, live);
    }
  }
}

static void walk_member(MsLivePass *pass, const MsExpr *expr, MsLiveSet *live) {
  const MsExpr *root = NULL;
  uint32_t binding = 0;
  MsLivePath path = {0};
  if (ms_bind_field_chain(pass->facts, pass->arena, expr, &root, &binding, &path)) {
    ms_live_record(pass, root->id, expr->id, binding, path, live);
    return;
  }
  ms_live_expr(pass, expr->u.member.left, live);
}

static void walk_binary(MsLivePass *pass, const MsExpr *expr, MsLiveSet *live) {
  if (expr->op == MS_B_AND || expr->op == MS_B_OR) {
    /* The right operand runs on some paths only. */
    MsLiveSet skipped = ms_live_clone(live);
    ms_live_expr(pass, expr->u.bin.right, live);
    ms_live_join(live, &skipped);
    ms_live_set_free(&skipped);
  } else {
    ms_live_expr(pass, expr->u.bin.right, live);
  }
  ms_live_expr(pass, expr->u.bin.left, live);
}

static void walk_call(MsLivePass *pass, const MsExpr *expr, MsLiveSet *live) {
  const uint32_t count = expr->u.call.args.len;
  const bool store = is_index_store(pass->names, expr);
  for (uint32_t index = 0; index < count; index++) {
    /* An index store walks its arguments in source order, so the key is the later use. */
    const uint32_t at = store ? index : count - 1 - index;
    ms_live_expr(pass, expr->u.call.args.ptr[at].value, live);
  }
  ms_live_expr(pass, expr->u.call.callee, live);
}

static void walk_match(MsLivePass *pass, const MsExpr *expr, MsLiveSet *live) {
  MsLiveSet after = ms_live_clone(live);
  MsLiveSet joined = {0};
  for (uint32_t index = expr->u.match.arms.len; index > 0; index--) {
    const MsArm *arm = expr->u.match.arms.ptr[index - 1];
    MsLiveSet arm_live = ms_live_clone(&after);
    if (arm->value != NULL) {
      ms_live_expr(pass, arm->value, &arm_live);
    }
    arm_live = ms_live_block(pass, arm->body, arm_live);
    ms_live_join(&joined, &arm_live);
    ms_live_set_free(&arm_live);
  }
  ms_live_set_free(&after);
  ms_live_set_free(live);
  *live = joined;
  ms_live_expr(pass, expr->u.match.scrutinee, live);
}

static void walk_lambda(MsLivePass *pass, const MsExpr *expr, MsLiveSet *live) {
  MsBindingList captures = ms_bind_captures(pass->facts, expr);
  /* The closure may run again, so its captured variables never die in its body. */
  MsLiveSet captured = {0};
  for (size_t index = 0; index < captures.len; index++) {
    ms_live_insert(&captured, captures.ptr[index], no_path, expr->id);
  }
  const MsLiveSet saved_exit = pass->exit;
  const MsLiveStack saved_breaks = pass->breaks;
  const MsLiveStack saved_continues = pass->continues;
  pass->exit = ms_live_clone(&captured);
  pass->breaks = (MsLiveStack){0};
  pass->continues = (MsLiveStack){0};
  MsLiveSet inner = ms_live_block(pass, expr->u.lambda.body, captured);
  ms_live_set_free(&inner);
  ms_live_set_free(&pass->exit);
  pass->exit = saved_exit;
  pass->breaks = saved_breaks;
  pass->continues = saved_continues;
  for (size_t index = 0; index < captures.len; index++) {
    const uint32_t binding = captures.ptr[index];
    ms_live_record(pass, expr->id, expr->id, binding, no_path, live);
    const MsNode at = ms_live_get(live, binding | MS_LIVE_STORED_BIT, no_path);
    if (at != MS_NO_NODE) {
      ms_node_map_put(&pass->out->assigned_after, ms_live_key(expr->id, binding), at);
    }
  }
  ms_binding_list_free(&captures);
}

void ms_live_expr(MsLivePass *pass, const MsExpr *expr, MsLiveSet *live) {
  uint32_t binding = 0;
  switch ((MsExprKind)expr->kind) {
  case MS_E_NUMBER:
  case MS_E_BOOL:
  case MS_E_VOID:
    return;
  case MS_E_TEXT:
    walk_text(pass, expr, live);
    return;
  case MS_E_NAME:
    if (ms_bind_of(pass->facts, expr->id, &binding)) {
      ms_live_record(pass, expr->id, expr->id, binding, no_path, live);
    }
    return;
  case MS_E_MEMBER:
    walk_member(pass, expr, live);
    return;
  case MS_E_APPLY:
    if (expr->u.apply.value != NULL) {
      ms_live_expr(pass, expr->u.apply.value, live);
    }
    ms_live_expr(pass, expr->u.apply.left, live);
    return;
  case MS_E_INDEX:
    ms_live_expr(pass, expr->u.bin.right, live);
    ms_live_expr(pass, expr->u.bin.left, live);
    return;
  case MS_E_PROBE:
  case MS_E_UNARY:
    ms_live_expr(pass, expr->u.bin.left, live);
    return;
  case MS_E_LIST:
    for (uint32_t index = expr->u.list.len; index > 0; index--) {
      ms_live_expr(pass, expr->u.list.ptr[index - 1], live);
    }
    return;
  case MS_E_MAP:
    for (uint32_t index = expr->u.map.len; index > 0; index--) {
      ms_live_expr(pass, expr->u.map.ptr[index - 1].value, live);
      ms_live_expr(pass, expr->u.map.ptr[index - 1].key, live);
    }
    return;
  case MS_E_BINARY:
    walk_binary(pass, expr, live);
    return;
  case MS_E_LAMBDA:
    walk_lambda(pass, expr, live);
    return;
  case MS_E_CALL:
    walk_call(pass, expr, live);
    return;
  case MS_E_MATCH:
    walk_match(pass, expr, live);
    return;
  }
}

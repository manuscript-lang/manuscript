/* compiler/own/live_stmt.c: the statement half of the liveness walk, with loops and the entry point. */
#include "compiler/own/live_pass.h"

static const MsLivePath no_path = {0};

/* A pattern defines its bindings: the old value's life, and anything before the definition, ends. */
static void define_pattern(MsLivePass *pass, const MsPattern *pattern, MsLiveSet *live) {
  uint32_t binding = 0;
  switch ((MsPatternKind)pattern->kind) {
  case MS_P_NAME:
    if (ms_bind_of(pass->facts, pattern->id, &binding)) {
      ms_live_kill(live, binding);
    }
    return;
  case MS_P_LIST:
    for (uint32_t index = 0; index < pattern->u.list.len; index++) {
      define_pattern(pass, pattern->u.list.ptr[index], live);
    }
    return;
  case MS_P_TYPE:
    for (uint32_t index = 0; index < pattern->u.fields.len; index++) {
      define_pattern(pass, pattern->u.fields.ptr[index].pattern, live);
    }
    return;
  }
}

/* The store to a binding ends the old value's life, and marks it assigned again for closures made before. */
static void store_name(MsLivePass *pass, const MsStmt *stmt, MsLiveSet *live) {
  uint32_t binding = 0;
  if (!ms_bind_of(pass->facts, stmt->id, &binding)) {
    return;
  }
  ms_live_kill(live, binding);
  ms_live_kill(live, binding | MS_LIVE_STORED_BIT);
  ms_live_insert(live, binding | MS_LIVE_STORED_BIT, no_path, stmt->u.assign.value->id);
}

static void walk_assign(MsLivePass *pass, const MsStmt *stmt, MsLiveSet *live) {
  const MsExpr *target = stmt->u.assign.target;
  const MsExpr *root = NULL;
  uint32_t binding = 0;
  MsLivePath path = {0};
  if (!stmt->u.assign.member_target) {
    store_name(pass, stmt, live);
  } else if (ms_bind_field_chain(pass->facts, pass->arena, target, &root, &binding, &path)) {
    /* The store ends the life of what the place held and of the parts below it; the binding is used. */
    ms_live_remove_prefix(live, binding, path);
    MsName *names = MS_ARENA_NEW_ARRAY(pass->arena, MsName, (size_t)path.len + 1);
    for (uint32_t index = 0; index < path.len; index++) {
      names[index] = path.names[index];
    }
    names[path.len] = MS_LIVE_STORE;
    ms_live_record(pass, root->id, target->id, binding, (MsLivePath){.names = names, .len = path.len + 1}, live);
  } else {
    ms_live_expr(pass, target, live);
  }
  ms_live_expr(pass, stmt->u.assign.value, live);
}

/* A loop head fixpoint: the next iteration's reads keep bindings live. */
static MsLiveSet looping(MsLivePass *pass, const MsExpr *cond, const MsExpr *iter, const MsStmt *each,
                         MsStmts body, MsLiveSet after) {
  MsLiveSet head = ms_live_clone(&after);
  for (;;) {
    ms_live_stack_push(&pass->breaks, ms_live_clone(&after));
    ms_live_stack_push(&pass->continues, ms_live_clone(&head));
    MsLiveSet entry = ms_live_block(pass, body, ms_live_clone(&head));
    MsLiveSet popped = {0};
    if (ms_live_stack_pop(&pass->continues, &popped)) {
      ms_live_set_free(&popped);
    }
    if (ms_live_stack_pop(&pass->breaks, &popped)) {
      ms_live_set_free(&popped);
    }
    uint32_t variable = 0;
    if (each != NULL && ms_bind_of(pass->facts, each->id, &variable)) {
      ms_live_kill(&entry, variable); /* defined per iteration, inside the loop */
    }
    ms_live_join(&entry, &after);
    if (cond != NULL) {
      ms_live_expr(pass, cond, &entry);
    }
    const size_t before = head.len;
    ms_live_join(&head, &entry);
    ms_live_set_free(&entry);
    if (head.len == before) {
      break;
    }
  }
  ms_live_set_free(&after);
  if (iter != NULL) {
    ms_live_expr(pass, iter, &head);
  }
  return head;
}

/* The live set at the innermost loop's top of stack, or empty outside a loop. */
static MsLiveSet from_stack(const MsLiveStack *stack) {
  return stack->len == 0 ? (MsLiveSet){0} : ms_live_clone(&stack->ptr[stack->len - 1]);
}

static MsLiveSet walk_if(MsLivePass *pass, const MsStmt *stmt, MsLiveSet live) {
  MsLiveSet joined = ms_live_block(pass, stmt->u.branch.body, ms_live_clone(&live));
  if (stmt->u.branch.binding != NULL) {
    define_pattern(pass, stmt->u.branch.binding, &joined);
  }
  MsLiveSet other = ms_live_block(pass, stmt->u.branch.else_body, live);
  ms_live_join(&joined, &other);
  ms_live_set_free(&other);
  ms_live_expr(pass, stmt->u.branch.cond, &joined);
  return joined;
}

static MsLiveSet walk_stmt(MsLivePass *pass, const MsStmt *stmt, MsLiveSet live) {
  switch ((MsStmtKind)stmt->kind) {
  case MS_S_BIND:
    define_pattern(pass, stmt->u.bind.pattern, &live);
    ms_live_expr(pass, stmt->u.bind.value, &live);
    return live;
  case MS_S_ASSIGN:
    walk_assign(pass, stmt, &live);
    return live;
  case MS_S_CALL:
    ms_live_expr(pass, stmt->u.expr, &live);
    return live;
  case MS_S_RETURN:
    ms_live_set_free(&live);
    live = ms_live_clone(&pass->exit);
    if (stmt->u.expr != NULL) {
      ms_live_expr(pass, stmt->u.expr, &live);
    }
    return live;
  case MS_S_BREAK:
    ms_live_set_free(&live);
    return from_stack(&pass->breaks);
  case MS_S_CONTINUE:
    ms_live_set_free(&live);
    return from_stack(&pass->continues);
  case MS_S_IF:
    return walk_if(pass, stmt, live);
  case MS_S_WHILE:
    return looping(pass, stmt->u.loop.cond, NULL, NULL, stmt->u.loop.body, live);
  case MS_S_FOR:
    return looping(pass, NULL, stmt->u.each.iter, stmt, stmt->u.each.body, live);
  }
  return live;
}

MsLiveSet ms_live_block(MsLivePass *pass, MsStmts body, MsLiveSet live) {
  for (uint32_t index = body.len; index > 0; index--) {
    live = walk_stmt(pass, body.ptr[index - 1], live);
  }
  return live;
}

static void free_stack(MsLiveStack *stack) {
  for (size_t index = 0; index < stack->len; index++) {
    ms_live_set_free(&stack->ptr[index]);
  }
  ms_live_stack_free(stack);
}

MsLiveness ms_live_compute(const MsFacts *facts, const MsNames *names, MsArena *arena, MsStmts body) {
  MsLiveness out = {0};
  MsLivePass pass = {.facts = facts, .arena = arena, .names = names, .out = &out};
  MsLiveSet end = ms_live_block(&pass, body, (MsLiveSet){0});
  ms_live_set_free(&end);
  free_stack(&pass.breaks);
  free_stack(&pass.continues);
  ms_live_set_free(&pass.exit);
  return out;
}

void ms_liveness_free(MsLiveness *liveness) {
  ms_live_map_free(&liveness->uses);
  ms_live_map_free(&liveness->places);
  ms_node_map_free(&liveness->assigned_after);
}

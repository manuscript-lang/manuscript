/* compiler/own/moves.c: a moved value used again (see moves.h). */
#include "compiler/own/moves.h"

#include "compiler/check/methods.h"
#include "compiler/own/bind.h"
#include "compiler/own/live.h"
#include "compiler/syntax/walk.h"

/* A name use, to say where a later use is. */
typedef struct Spot {
  MsNode node;
  MsPos pos;
} Spot;

MS_LIST_DEFINE(SpotList, spot_list, Spot)

typedef struct Moves {
  MsCheckProgram *program;
  uint32_t module;
  const MsFacts *facts;
  const MsLiveness *live;
  SpotList spots;
} Moves;

static void note_spot(void *ctx, const MsExpr *expr) {
  Moves *pass = ctx;
  if (expr->kind == MS_E_NAME || expr->kind == MS_E_LAMBDA) {
    spot_list_push(&pass->spots, (Spot){expr->id, expr->pos});
  }
}

static MsPos spot_of(const Moves *pass, MsNode node) {
  for (size_t index = 0; index < pass->spots.len; index++) {
    if (pass->spots.ptr[index].node == node) {
      return pass->spots.ptr[index].pos;
    }
  }
  return (MsPos){0};
}

static void report(const Moves *pass, const MsExpr *expr, MsNode next) {
  const MsPos later = spot_of(pass, next);
  const MsTy ty = ms_facts_type(pass->facts, expr->id);
  const MsSpan name = ms_names_span(pass->program->names, expr->u.sym);
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "`");
  ms_strbuild_append(&text, name);
  ms_strbuild_append_text(&text, "` is moved here but used again");
  const bool again = next == expr->id;
  if (again) {
    ms_strbuild_append_text(&text, " on the next loop iteration");
  } else if (later.line != 0) {
    ms_strbuild_append_text(&text, " at ");
    ms_strbuild_append_u64(&text, later.line);
    ms_strbuild_append_text(&text, ":");
    ms_strbuild_append_u64(&text, later.column);
  }
  if (ty != MS_TY_NONE && ms_ty_kind(&pass->program->types, ty) == MS_TY_FUNCTION) {
    ms_strbuild_append_text(&text, "; a function value has one owner and cannot be cloned, so move it only at its last use or declare a named `fn`, which can be passed as often as needed");
  } else if (ty != MS_TY_NONE && ms_check_holds_resource(pass->program, ty)) {
    ms_strbuild_append_text(&text, "; a resource has one owner and cannot be cloned, so move it only at its last use, or pass it where it is only read");
  } else {
    ms_strbuild_append_text(&text, "; a value has one owner, so move it only at its last use, or pass `");
    ms_strbuild_append(&text, name);
    ms_strbuild_append_text(&text, ".clone()` if the original is still needed");
  }
  ms_check_report(pass->program, pass->module, expr->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

static void visit_expr(void *ctx, const MsExpr *expr) {
  const Moves *pass = ctx;
  uint32_t binding = 0;
  if (expr->kind != MS_E_NAME || ms_facts_use(pass->facts, expr->id) != MS_USE_MOVE ||
      !ms_bind_of(pass->facts, expr->id, &binding)) {
    return;
  }
  const MsUseLive *use = ms_live_map_get(&pass->live->uses, ms_live_key(expr->id, binding));
  if (use != NULL && !use->last) {
    report(pass, expr, use->next);
  }
}

static void check_body(Moves *pass, MsArena *arena, MsStmts body, MsParams params) {
  if (body.len == 0) {
    return;
  }
  MsLiveness live = ms_live_compute(pass->facts, pass->program->names, arena, body);
  pass->live = &live;
  ms_walk_callable(&(MsVisitor){.ctx = pass, .expr = note_spot}, params, body);
  ms_walk_callable(&(MsVisitor){.ctx = pass, .expr = visit_expr}, params, body);
  spot_list_clear(&pass->spots);
  ms_liveness_free(&live);
}

static void check_decl(Moves *pass, MsArena *arena, const MsDecl *decl) {
  switch ((MsDeclKind)decl->kind) {
  case MS_D_FN:
    check_body(pass, arena, decl->u.fn.body, decl->u.fn.params);
    return;
  case MS_D_TEST:
    check_body(pass, arena, decl->u.test.body, (MsParams){0});
    return;
  case MS_D_IMPL:
    for (uint32_t index = 0; index < decl->u.impl.methods.len; index++) {
      const MsFunc *func = &decl->u.impl.methods.ptr[index]->func;
      check_body(pass, arena, func->body, func->params);
    }
    return;
  case MS_D_CONST:
  case MS_D_TYPE:
  case MS_D_ENUM:
  case MS_D_ALIAS:
  case MS_D_INTERFACE:
    return;
  }
}

void ms_own_moves(MsCheckProgram *program) {
  MsArena arena = ms_arena_new();
  for (uint32_t module = 0; module < program->user_modules; module++) {
    Moves pass = {.program = program, .module = module, .facts = &program->modules.ptr[module].facts};
    const MsModule *tree = program->modules.ptr[module].tree;
    for (uint32_t index = 0; index < tree->ndecls; index++) {
      check_decl(&pass, &arena, tree->decls[index]);
    }
    spot_list_free(&pass.spots);
  }
  ms_arena_free(&arena);
}

/* compiler/own/borrows.c: a source changed while a binding borrowing it is still used (see borrows.h). */
#include "compiler/own/borrows.h"

#include "compiler/check/methods.h"
#include "compiler/own/bind.h"
#include "compiler/own/class.h"
#include "compiler/syntax/walk.h"

typedef struct Borrow {
  uint32_t binding; /* the borrowing binding */
  MsName name;
  MsPos at; /* where it is bound */
  uint32_t after; /* the offset its initializer ends at */
  bool mutable_;
  uint32_t root; /* the binding it borrows from */
} Borrow;

typedef struct Change {
  uint32_t root;
  MsPos pos;     /* where the changed place starts */
  uint32_t end;  /* the offset it ends at */
  bool assign;
} Change;

typedef struct Use {
  uint32_t binding;
  uint32_t offset;
} Use;

MS_LIST_DEFINE(BorrowList, borrow_list, Borrow)
MS_LIST_DEFINE(ChangeList, change_list, Change)
MS_LIST_DEFINE(UseList, use_list, Use)

typedef struct Borrows {
  MsCheckProgram *program;
  MsClassifier *classes;
  uint32_t module;
  MsFacts *facts;
  MsSpan source;
  BorrowList borrows;
  ChangeList changes;
  UseList uses;
} Borrows;

/* The function-wide id of the local or parameter `node` names: the checker numbers locals densely and gives
 * parameters their own index space. */
static bool local_of(const MsFacts *facts, MsNode node, uint32_t *id) {
  const MsRef *ref = ms_facts_ref(facts, node);
  if (ref == NULL || (ref->kind != MS_REF_LOCAL && ref->kind != MS_REF_PARAM)) {
    return false;
  }
  *id = ref->kind == MS_REF_PARAM ? ref->local | 0x80000000u : ref->local;
  return true;
}

/* Whether the declaration `ref` names declares its result `move`. */
static bool declares_move(const MsCheckProgram *program, const MsRef *ref) {
  for (size_t index = 0; index < program->methods.len; index++) {
    const MsMethodEntry *entry = &program->methods.ptr[index];
    if (entry->module == ref->decl.module && entry->source->id == ref->decl.node) {
      return entry->source->func.result_moves;
    }
  }
  const MsModule *tree = program->modules.ptr[ref->decl.module].tree;
  for (uint32_t index = 0; index < tree->ndecls; index++) {
    const MsDecl *decl = tree->decls[index];
    if (decl->kind == MS_D_FN && decl->id == ref->decl.node) {
      return decl->u.fn.result_moves;
    }
    if (decl->kind != MS_D_INTERFACE) {
      continue;
    }
    for (uint32_t at = 0; at < decl->u.iface.methods.len; at++) {
      if (decl->u.iface.methods.ptr[at]->id == ref->decl.node) {
        return decl->u.iface.methods.ptr[at]->func.result_moves;
      }
    }
  }
  return false;
}

static bool is_value_ref(MsRefKind kind) {
  return kind == MS_REF_FUNCTION || kind == MS_REF_METHOD || kind == MS_REF_NATIVE || kind == MS_REF_OPERATION;
}

static bool owns_memory(Borrows *pass, const MsExpr *expr) {
  const MsTy ty = ms_facts_type(pass->facts, expr->id);
  return ty != MS_TY_NONE && ms_class_of(pass->classes, ty) != MS_CLASS_COPY;
}

static bool origin_of_call(Borrows *pass, const MsExpr *call, uint32_t *root);

/* The local an argument expression borrows from: a local, a field of one, or a borrowing call on one. */
static bool origin_of_arg(Borrows *pass, const MsExpr *arg, uint32_t *root) {
  const MsExpr *at = arg;
  while (at->kind == MS_E_MEMBER) {
    at = at->u.member.left;
  }
  if (at->kind == MS_E_NAME && owns_memory(pass, arg)) {
    return local_of(pass->facts, at->id, root);
  }
  if (arg->kind == MS_E_UNARY && arg->op == MS_U_TRY) {
    return origin_of_arg(pass, arg->u.bin.left, root);
  }
  return arg->kind == MS_E_CALL && origin_of_call(pass, arg, root);
}

/* A call whose result is not declared `move` borrows from its first argument that has an origin. */
static bool origin_of_call(Borrows *pass, const MsExpr *call, uint32_t *root) {
  const MsCall *fact = ms_facts_call(pass->facts, call->id);
  if (fact == NULL || !is_value_ref(fact->callee.kind) || declares_move(pass->program, &fact->callee) ||
      !owns_memory(pass, call)) {
    return false;
  }
  const MsExpr *callee = call->u.call.callee;
  if (callee->kind == MS_E_MEMBER && origin_of_arg(pass, callee->u.member.left, root)) {
    return true;
  }
  for (uint32_t index = 0; index < call->u.call.args.len; index++) {
    if (origin_of_arg(pass, call->u.call.args.ptr[index].value, root)) {
      return true;
    }
  }
  return false;
}

static void note_bind(Borrows *pass, const MsStmt *stmt) {
  const MsPattern *pattern = stmt->u.bind.pattern;
  const MsExpr *value = stmt->u.bind.value;
  uint32_t root = 0;
  uint32_t binding = 0;
  if (pattern == NULL || pattern->kind != MS_P_NAME || value == NULL || !origin_of_arg(pass, value, &root) ||
      value->kind == MS_E_NAME || value->kind == MS_E_MEMBER || !local_of(pass->facts, pattern->id, &binding)) {
    return;
  }
  borrow_list_push(&pass->borrows, (Borrow){.binding = binding, .name = pattern->u.name, .at = pattern->pos, .after = value->end.offset,
                                            .mutable_ = stmt->u.bind.is_mutable, .root = root});
}

/* Records the place a store or `var` argument changes. */
static void note_change(Borrows *pass, const MsExpr *place, bool assign) {
  if (place == NULL) {
    return;
  }
  const MsExpr *at = place;
  for (;;) {
    MsExpr *left = NULL;
    MsExpr *index = NULL;
    if (at->kind == MS_E_MEMBER) {
      at = at->u.member.left;
    } else if (ms_expr_index(at, &left, &index)) {
      at = left;
    } else {
      break;
    }
  }
  uint32_t root = 0;
  if (at->kind == MS_E_NAME && local_of(pass->facts, at->id, &root)) {
    change_list_push(&pass->changes, (Change){.root = root, .pos = ms_expr_start(place), .end = place->end.offset, .assign = assign});
  }
}

static void visit_stmt(void *ctx, const MsStmt *stmt) {
  Borrows *pass = ctx;
  if (stmt->kind == MS_S_BIND) {
    note_bind(pass, stmt);
  } else if (stmt->kind == MS_S_ASSIGN) {
    note_change(pass, stmt->u.assign.target, true);
    uint32_t root = 0;
    if (!stmt->u.assign.member_target && local_of(pass->facts, stmt->id, &root)) {
      const uint32_t length = (uint32_t)ms_names_span(pass->program->names, stmt->u.assign.name).len;
      change_list_push(&pass->changes, (Change){.root = root, .pos = stmt->pos, .end = stmt->pos.offset + length,
                                                .assign = true});
    }
  }
}

static void visit_expr(void *ctx, const MsExpr *expr) {
  Borrows *pass = ctx;
  uint32_t binding = 0;
  if (expr->kind == MS_E_NAME && local_of(pass->facts, expr->id, &binding)) {
    use_list_push(&pass->uses, (Use){.binding = binding, .offset = expr->pos.offset});
    return;
  }
  const MsCall *fact = expr->kind == MS_E_CALL ? ms_facts_call(pass->facts, expr->id) : NULL;
  for (uint32_t index = 0; fact != NULL && index < fact->arg_count; index++) {
    const MsCallArg *arg = &fact->args[index];
    if (arg->source != MS_ARG_WRITTEN || (arg->flags & MS_PARAM_VAR) == 0) {
      continue;
    }
    const MsExpr *callee = expr->u.call.callee;
    if (callee->kind == MS_E_MEMBER && arg->node.node == callee->u.member.left->id) {
      note_change(pass, callee->u.member.left, false);
      continue;
    }
    for (uint32_t at = 0; at < expr->u.call.args.len; at++) {
      if (expr->u.call.args.ptr[at].value->id == arg->node.node) {
        note_change(pass, expr->u.call.args.ptr[at].value, false);
      }
    }
  }
}

static bool used_after(const Borrows *pass, uint32_t binding, uint32_t offset) {
  for (size_t index = 0; index < pass->uses.len; index++) {
    if (pass->uses.ptr[index].binding == binding && pass->uses.ptr[index].offset > offset) {
      return true;
    }
  }
  return false;
}

static void append_name(const Borrows *pass, MsStrBuild *text, MsName name) {
  ms_strbuild_append(text, ms_names_span(pass->program->names, name));
}

static void report(Borrows *pass, const Borrow *borrow, const Change *change) {
  const MsPos start = change->pos;
  if (change->end <= start.offset || change->end > pass->source.len) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, change->assign ? "cannot reassign `" : "cannot change `");
  ms_strbuild_append(&text, (MsSpan){pass->source.ptr + start.offset, change->end - start.offset});
  ms_strbuild_append_text(&text, "` while `");
  append_name(pass, &text, borrow->name);
  ms_strbuild_append_text(&text, borrow->mutable_ ? "` borrows it (mutable borrow, at " : "` borrows it (binding of a part of it, at ");
  ms_strbuild_append_u64(&text, borrow->at.line);
  ms_strbuild_append_text(&text, ":");
  ms_strbuild_append_u64(&text, borrow->at.column);
  ms_strbuild_append_text(&text, "); finish using `");
  append_name(pass, &text, borrow->name);
  ms_strbuild_append_text(&text, "` before this, or give `");
  append_name(pass, &text, borrow->name);
  ms_strbuild_append_text(&text, "` its own value by ending its initializer with `.clone()`");
  ms_check_report(pass->program, pass->module, start, MS_CHECK_TYPE, ms_strbuild_finish(&text));
}

/* Each borrow reports its first later change of the source when the borrower is still used after it. */
static void judge(Borrows *pass) {
  for (size_t at = 0; at < pass->borrows.len; at++) {
    const Borrow *borrow = &pass->borrows.ptr[at];
    for (size_t index = 0; index < pass->changes.len; index++) {
      const Change *change = &pass->changes.ptr[index];
      const uint32_t offset = change->pos.offset;
      if (change->root == borrow->root && offset >= borrow->after && used_after(pass, borrow->binding, offset)) {
        report(pass, borrow, change);
        break;
      }
    }
  }
  borrow_list_clear(&pass->borrows);
  change_list_clear(&pass->changes);
  use_list_clear(&pass->uses);
}

void ms_own_borrows(MsCheckProgram *program) {
  if (program->diagnostics.len != 0) {
    return;
  }
  MsClassifier classes = ms_class_new(program);
  for (uint32_t module = 0; module < program->user_modules; module++) {
    Borrows pass = {.program = program, .classes = &classes, .module = module,
                    .facts = &program->modules.ptr[module].facts, .source = program->modules.ptr[module].source};
    const MsModule *tree = program->modules.ptr[module].tree;
    const MsVisitor visitor = {.ctx = &pass, .stmt = visit_stmt, .expr = visit_expr};
    for (uint32_t index = 0; index < tree->ndecls; index++) {
      ms_walk_decl(&visitor, tree->decls[index]);
      judge(&pass);
    }
    borrow_list_free(&pass.borrows);
    change_list_free(&pass.changes);
    use_list_free(&pass.uses);
  }
  ms_class_free(&classes);
}

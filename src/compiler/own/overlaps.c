/* compiler/own/overlaps.c: the operands of one call that overlap (see overlaps.h). */
#include "compiler/own/overlaps.h"

#include "compiler/own/bind.h"
#include "compiler/own/class.h"
#include "compiler/own/expr_text.h"
#include "compiler/own/places.h"
#include "compiler/syntax/parse.h"
#include "compiler/syntax/walk.h"

typedef enum Mode { MODE_BORROW, MODE_MOVE, MODE_MUTATE } Mode;
typedef enum OperandKind { OP_RECEIVER, OP_CALLEE, OP_ARGUMENT } OperandKind;

/* A place an operand keeps hold of while the call runs, and whether the operand moves or changes it. */
typedef struct Held {
  MsPlace place;
  bool write;
} Held;

MS_LIST_DEFINE(HeldList, held_list, Held)
MS_LIST_DEFINE(PlaceList, place_list, MsPlace)

typedef struct Operand {
  OperandKind kind;
  const MsExpr *expr;
  HeldList held;      /* what the operand holds for the whole call */
  PlaceList passing;  /* what runs inside the operand's own evaluation and changes or moves it */
} Operand;

MS_LIST_DEFINE(OperandList, operand_list, Operand)

typedef struct Overlaps {
  MsCheckProgram *program;
  MsClassifier *classes;
  MsArena *arena;
  uint32_t module;
  const MsFacts *facts;
  MsSpan source;
} Overlaps;

static MsSpan name_span(const Overlaps *pass, MsName name) {
  return ms_names_span(pass->program->names, name);
}

/* ---- places ---- */

/* A list index written as an integer literal: decimal, `0x` or `0b`, with `_` separators. */
static bool literal_index(const Overlaps *pass, const MsExpr *index, uint64_t *value) {
  if (index->kind != MS_E_NUMBER) {
    return false;
  }
  const MsSpan text = ms_names_span(pass->program->names, index->u.sym);
  unsigned base = 10;
  size_t at = 0;
  if (text.len > 2 && text.ptr[0] == '0' && (text.ptr[1] == 'x' || text.ptr[1] == 'b')) {
    base = text.ptr[1] == 'x' ? 16 : 2;
    at = 2;
  }
  uint64_t number = 0;
  for (; at < text.len; at++) {
    const char c = (char)text.ptr[at];
    const int digit = c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
    if (c == '_') {
      continue;
    }
    if (digit < 0 || (unsigned)digit >= base || number > (UINT64_MAX - (uint64_t)digit) / base) {
      return false;
    }
    number = number * base + (uint64_t)digit;
  }
  *value = number;
  return true;
}

/* The place `expr` names: a local or parameter, a field path below it, or an element of one. */
static bool place_of(Overlaps *pass, const MsExpr *expr, MsPlace *out) {
  MsExpr *left = NULL;
  MsExpr *index = NULL;
  uint32_t binding = 0;
  if (expr->kind == MS_E_NAME) {
    if (!ms_bind_of(pass->facts, expr->id, &binding)) {
      return false;
    }
    *out = ms_place_local(binding);
    return true;
  }
  if (expr->kind == MS_E_MEMBER) {
    MsPlace base;
    if (!place_of(pass, expr->u.member.left, &base)) {
      return false;
    }
    *out = ms_place_then(pass->arena, base, (MsStep){.kind = MS_STEP_FIELD, .name = expr->u.member.name});
    return true;
  }
  if (ms_expr_index(expr, &left, &index)) {
    MsPlace base;
    if (!place_of(pass, left, &base)) {
      return false;
    }
    uint64_t at = 0;
    const MsStep step = literal_index(pass, index, &at) ? (MsStep){.kind = MS_STEP_INDEX, .index = at}
                                                          : (MsStep){.kind = MS_STEP_ELEMENT};
    *out = ms_place_then(pass->arena, base, step);
    return true;
  }
  return false;
}

static bool is_copy(Overlaps *pass, const MsExpr *expr) {
  const MsTy ty = ms_facts_type(pass->facts, expr->id);
  return ty == MS_TY_NONE || ms_class_of(pass->classes, ty) == MS_CLASS_COPY;
}

/* The keys that select an element of a held place stay read for the whole call. */
static void selecting_keys(Overlaps *pass, const MsExpr *expr, HeldList *out) {
  MsExpr *left = NULL;
  MsExpr *index = NULL;
  if (expr->kind == MS_E_MEMBER) {
    selecting_keys(pass, expr->u.member.left, out);
  } else if (ms_expr_index(expr, &left, &index)) {
    selecting_keys(pass, left, out);
    MsPlace key;
    if (!is_copy(pass, index) && place_of(pass, index, &key)) {
      held_list_push(out, (Held){.place = key, .write = false});
    }
  }
}

/* The places an operand keeps hold of while the call runs: a variable changed or moved by it, or a value read in place.
 * Copies and computed values are finished before the call starts. */
static void held_of(Overlaps *pass, const MsExpr *expr, Mode mode, HeldList *out) {
  if (expr->kind == MS_E_LAMBDA || (mode != MODE_MUTATE && is_copy(pass, expr))) {
    return;
  }
  MsPlace place;
  if (place_of(pass, expr, &place)) {
    held_list_push(out, (Held){.place = place, .write = mode != MODE_BORROW});
    selecting_keys(pass, expr, out);
  }
}

/* ---- what a call changes ---- */

static Mode mode_of_flags(uint8_t flags) {
  return (flags & MS_PARAM_VAR) != 0 ? MODE_MUTATE : (flags & MS_PARAM_MOVE) != 0 ? MODE_MOVE : MODE_BORROW;
}

/* Whether any written argument is a function that changes its parameter in place (`fn(var T)`), which changes the
 * receiver's elements. */
static bool callback_changes_elements(Overlaps *pass, const MsExpr *call, const MsCall *fact) {
  const MsTyTable *types = &pass->program->types;
  for (uint32_t at = 0; at < call->u.call.args.len; at++) {
    const MsTy ty = ms_facts_type(pass->facts, call->u.call.args.ptr[at].value->id);
    if (ty == MS_TY_NONE || ms_ty_kind(types, ty) != MS_TY_FUNCTION) {
      continue;
    }
    for (size_t param = 0; param < ms_ty_param_count(types, ty); param++) {
      if ((ms_ty_params(types, ty)[param].flags & MS_PARAM_VAR) != 0) {
        return true;
      }
    }
  }
  (void)fact;
  return false;
}

static bool is_receiver(const MsExpr *call, const MsCallArg *arg) {
  const MsExpr *callee = call->u.call.callee;
  return callee->kind == MS_E_MEMBER && arg->node.node == callee->u.member.left->id;
}

static Mode receiver_mode(Overlaps *pass, const MsExpr *call, const MsCall *fact, const MsCallArg *arg) {
  const Mode declared = mode_of_flags(arg->flags);
  return declared == MODE_BORROW && callback_changes_elements(pass, call, fact) ? MODE_MUTATE : declared;
}

/* The places the call `call` changes or moves: a `var` or consumed argument place, or a receiver changed in place. */
static void own_writes(Overlaps *pass, const MsExpr *call, PlaceList *out) {
  const MsCall *fact = ms_facts_call(pass->facts, call->id);
  if (fact == NULL || fact->constructor) {
    return;
  }
  for (uint32_t index = 0; index < fact->arg_count; index++) {
    const MsCallArg *arg = &fact->args[index];
    if (arg->source != MS_ARG_WRITTEN) {
      continue;
    }
    const Mode mode = is_receiver(call, arg) ? receiver_mode(pass, call, fact, arg) : mode_of_flags(arg->flags);
    if (mode == MODE_BORROW) {
      continue;
    }
    const MsExpr *value = NULL;
    if (is_receiver(call, arg)) {
      value = call->u.call.callee->u.member.left;
    }
    for (uint32_t at = 0; value == NULL && at < call->u.call.args.len; at++) {
      if (call->u.call.args.ptr[at].value->id == arg->node.node) {
        value = call->u.call.args.ptr[at].value;
      }
    }
    MsPlace place;
    if (value != NULL && place_of(pass, value, &place)) {
      place_list_push(out, place);
    }
  }
}

typedef struct Collect {
  Overlaps *pass;
  PlaceList *out;
  uint32_t lambdas; /* open closures: what they change is theirs, not the operand's */
} Collect;

static void collect_stmt(void *context, const MsStmt *stmt) {
  Collect *collect = context;
  if (collect->lambdas != 0 || stmt->kind != MS_S_ASSIGN) {
    return;
  }
  MsPlace place;
  if (stmt->u.assign.member_target) {
    if (place_of(collect->pass, stmt->u.assign.target, &place)) {
      place_list_push(collect->out, place);
    }
    return;
  }
  const MsRef *ref = ms_facts_ref(collect->pass->facts, stmt->id);
  if (ref != NULL && (ref->kind == MS_REF_LOCAL || ref->kind == MS_REF_PARAM)) {
    place_list_push(collect->out, ms_place_local(ref->decl.node));
  }
}

static void collect_expr(void *context, const MsExpr *expr) {
  Collect *collect = context;
  if (expr->kind == MS_E_LAMBDA) {
    collect->lambdas++;
  } else if (collect->lambdas == 0 && expr->kind == MS_E_CALL) {
    own_writes(collect->pass, expr, collect->out);
  }
}

static void collect_leave(void *context, const MsExpr *expr) {
  Collect *collect = context;
  if (expr->kind == MS_E_LAMBDA && collect->lambdas > 0) {
    collect->lambdas--;
  }
}

/* The places the calls and statements inside `expr` change or move, closures excluded. */
static void nested_writes(Overlaps *pass, const MsExpr *expr, PlaceList *out) {
  Collect collect = {.pass = pass, .out = out};
  ms_walk_expr(&(MsVisitor){.ctx = &collect, .stmt = collect_stmt, .expr = collect_expr, .leave_expr = collect_leave}, expr);
}

/* What a closure holds: each captured place it changes (moved or changed in place), and each other captured value that
 * is not a copy, read where the closure finds it. */
static void lambda_held(Overlaps *pass, const MsExpr *lambda, HeldList *out) {
  PlaceList writes = {0};
  Collect collect = {.pass = pass, .out = &writes};
  ms_walk_block(&(MsVisitor){.ctx = &collect, .stmt = collect_stmt, .expr = collect_expr, .leave_expr = collect_leave},
                lambda->u.lambda.body);
  MsBindingList captures = ms_bind_captures(pass->facts, lambda);
  for (size_t index = 0; index < captures.len; index++) {
    bool written = false;
    for (size_t at = 0; at < writes.len; at++) {
      if (writes.ptr[at].root == captures.ptr[index]) {
        held_list_push(out, (Held){.place = writes.ptr[at], .write = true});
        written = true;
      }
    }
    const MsTy ty = ms_facts_type(pass->facts, captures.ptr[index]);
    if (!written && ty != MS_TY_NONE && ms_class_of(pass->classes, ty) != MS_CLASS_COPY) {
      held_list_push(out, (Held){.place = ms_place_local(captures.ptr[index]), .write = false});
    }
  }
  ms_binding_list_free(&captures);
  place_list_free(&writes);
}

/* ---- reporting ---- */

static void append_operand(const Overlaps *pass, MsStrBuild *out, const Operand *operand) {
  if (operand->expr->kind == MS_E_LAMBDA) {
    ms_strbuild_append_text(out, "the closure at ");
    ms_strbuild_append_u64(out, operand->expr->pos.line);
    ms_strbuild_append_text(out, ":");
    ms_strbuild_append_u64(out, operand->expr->pos.column);
    return;
  }
  ms_strbuild_append_text(out, operand->kind == OP_RECEIVER ? "the receiver `"
                               : operand->kind == OP_CALLEE ? "the called value `"
                                                            : "argument `");
  ms_own_expr_text(out, pass->program->names, operand->expr);
  ms_strbuild_append_text(out, "`");
}

/* A changed place may not overlap another operand of the same call. A place an operand holds for the whole call clashes
 * with a change of it by another operand: one held for the call, or one finished while that operand was computed, which
 * leaves a held read or a held part dangling. */
static bool clashes(const OperandList *operands, size_t first, const MsPlace *place, bool held, size_t *other) {
  for (size_t index = 0; index < operands->len; index++) {
    if (index == first) {
      continue;
    }
    for (size_t at = 0; at < operands->ptr[index].held.len; at++) {
      const Held *entry = &operands->ptr[index].held.ptr[at];
      if (ms_place_overlaps(&entry->place, place) && (held || !entry->write || entry->place.count != 0)) {
        *other = index;
        return true;
      }
    }
  }
  return false;
}

static void check_overlap(Overlaps *pass, MsPos pos, MsSpan context, const OperandList *operands) {
  for (size_t index = 0; index < operands->len; index++) {
    const Operand *operand = &operands->ptr[index];
    size_t other = 0;
    bool found = false;
    for (size_t at = 0; !found && at < operand->held.len; at++) {
      found = operand->held.ptr[at].write && clashes(operands, index, &operand->held.ptr[at].place, true, &other);
    }
    for (size_t at = 0; !found && at < operand->passing.len; at++) {
      found = clashes(operands, index, &operand->passing.ptr[at], false, &other);
    }
    if (!found) {
      continue;
    }
    MsStrBuild text = ms_strbuild_new();
    append_operand(pass, &text, operand);
    ms_strbuild_append_text(&text, " of `");
    ms_strbuild_append(&text, context);
    ms_strbuild_append_text(&text, "` is moved or changed in place but overlaps ");
    append_operand(pass, &text, &operands->ptr[other]);
    ms_strbuild_append_text(&text, "; a moved or changed value cannot also be read or changed through another operand, so pass "
                                   "distinct variables or clone one first");
    ms_check_report(pass->program, pass->module, pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
    return;
  }
}

/* ---- calls ---- */

static void operands_free(OperandList *operands) {
  for (size_t index = 0; index < operands->len; index++) {
    held_list_free(&operands->ptr[index].held);
    place_list_free(&operands->ptr[index].passing);
  }
  operand_list_free(operands);
}

/* Fills each operand's nested writes, but only when some operand holds a place: only a held place can clash. */
static void judge(Overlaps *pass, MsPos pos, MsSpan context, OperandList *operands) {
  bool any = false;
  for (size_t index = 0; index < operands->len; index++) {
    any = any || operands->ptr[index].held.len != 0;
  }
  if (any) {
    for (size_t index = 0; index < operands->len; index++) {
      nested_writes(pass, operands->ptr[index].expr, &operands->ptr[index].passing);
    }
    check_overlap(pass, pos, context, operands);
  }
  operands_free(operands);
}

static Operand *add_operand(OperandList *operands, OperandKind kind, const MsExpr *expr) {
  operand_list_push(operands, (Operand){.kind = kind, .expr = expr});
  return &operands->ptr[operands->len - 1];
}

static void visit_call(Overlaps *pass, const MsExpr *call) {
  const MsCall *fact = ms_facts_call(pass->facts, call->id);
  if (fact == NULL || fact->constructor) {
    return;
  }
  const MsExpr *callee = call->u.call.callee;
  OperandList operands = {0};
  if (callee->kind == MS_E_MEMBER) {
    for (uint32_t index = 0; index < fact->arg_count; index++) {
      const MsCallArg *arg = &fact->args[index];
      if (arg->source == MS_ARG_WRITTEN && is_receiver(call, arg)) {
        Operand *operand = add_operand(&operands, OP_RECEIVER, callee->u.member.left);
        held_of(pass, callee->u.member.left, receiver_mode(pass, call, fact, arg), &operand->held);
      }
    }
  } else if (callee->kind == MS_E_NAME) {
    uint32_t binding = 0;
    MsPlace place;
    if (ms_bind_of(pass->facts, callee->id, &binding) && place_of(pass, callee, &place)) {
      held_list_push(&add_operand(&operands, OP_CALLEE, callee)->held, (Held){.place = place, .write = false});
    }
  }
  const bool store = callee->kind == MS_E_MEMBER && ms_span_is_text(name_span(pass, callee->u.member.name), MS_INDEX_SET);
  bool first_argument = true;
  for (uint32_t index = 0; index < fact->arg_count; index++) {
    const MsCallArg *arg = &fact->args[index];
    if (arg->source != MS_ARG_WRITTEN || is_receiver(call, arg)) {
      continue;
    }
    const MsExpr *value = NULL;
    for (uint32_t at = 0; value == NULL && at < call->u.call.args.len; at++) {
      if (call->u.call.args.ptr[at].value->id == arg->node.node) {
        value = call->u.call.args.ptr[at].value;
      }
    }
    if (value == NULL) {
      continue;
    }
    Operand *operand = add_operand(&operands, OP_ARGUMENT, value);
    if (value->kind == MS_E_LAMBDA) {
      lambda_held(pass, value, &operand->held);
    } else {
      held_of(pass, value, mode_of_flags(arg->flags), &operand->held);
      if (store && first_argument) {
        held_of(pass, value, MODE_BORROW, &operand->held); /* the key stays read until the store, so the value may not change it */
      }
    }
    first_argument = false;
  }
  const MsSpan context = callee->kind == MS_E_MEMBER ? name_span(pass, callee->u.member.name)
                         : callee->kind == MS_E_NAME  ? name_span(pass, callee->u.sym)
                                                      : ms_span_of_text("the callee");
  judge(pass, call->pos, context, &operands);
}

static void visit_expr(void *context, const MsExpr *expr) {
  if (expr->kind == MS_E_CALL) {
    visit_call(context, expr);
  }
}

void ms_own_overlaps(MsCheckProgram *program) {
  MsArena arena = ms_arena_new();
  MsClassifier classes = ms_class_new(program);
  for (uint32_t module = 0; module < (uint32_t)program->modules.len; module++) {
    Overlaps pass = {.program = program, .classes = &classes, .arena = &arena, .module = module,
                     .facts = &program->modules.ptr[module].facts, .source = program->modules.ptr[module].source};
    const MsModule *tree = program->modules.ptr[module].tree;
    const MsVisitor visitor = {.ctx = &pass, .expr = visit_expr};
    for (uint32_t index = 0; index < tree->ndecls; index++) {
      ms_walk_decl(&visitor, tree->decls[index]);
    }
  }
  ms_class_free(&classes);
  ms_arena_free(&arena);
}

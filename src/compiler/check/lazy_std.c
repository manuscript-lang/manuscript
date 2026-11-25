/* compiler/check/lazy_std.c: checks the bodies of bundled standard functions only when something reaches them.
 *
 * The bundled standard library is fixed per binary and `ms check --std` checks all of it, so a run needs the bodies
 * of the standard functions its code can reach, not every one the prelude defines: the ownership masks of a callee
 * come from its body, the rest of the prelude's bodies change no diagnostic of the program. The bodies are set aside
 * (blank) before the body walk, and every function or method a checked body names is given its body back and
 * checked, until nothing new is named. Lowering reads the same facts, so reach also covers what lowering calls
 * without a written reference (hooks.h). */
#include <string.h>
#include "base/alloc.h"
#include "base/fatal.h"
#include "base/sort.h"
#include "compiler/check/body.h"
#include "compiler/check/dispatch_targets.h"
#include "compiler/check/hooks.h"
#include "compiler/check/methods.h"
#include "compiler/check/properties.h"
#include "compiler/check/lazy_std.h"
#include "compiler/syntax/parse.h"
#include "compiler/syntax/walk.h"

static uint64_t node_key(uint32_t module, uint32_t node) {
  return (uint64_t)module << 32 | node;
}

static int64_t compare_keys(uint8_t *env, const uint8_t *left, const uint8_t *right) {
  (void)env;
  const MsMethodKey *a = (const MsMethodKey *)(const void *)left;
  const MsMethodKey *b = (const MsMethodKey *)(const void *)right;
  return a->key < b->key ? -1 : a->key > b->key;
}

static bool has_default(MsParams params) {
  for (uint32_t index = 0; index < params.len; index++) {
    if (params.ptr[index]->def != NULL) {
      return true;
    }
  }
  return false;
}

/* Lists a declaration with defaults and no body to set aside. */
static void list_defaults(MsCheckProgram *program, uint32_t module, uint32_t node, MsDecl *decl, MsMethod *method) {
  ms_deferred_body_list_push(&program->deferred_bodies,
                             (MsDeferredBody){.module = module, .node = node, .decl = decl, .method = method, .defaults_only = true});
  ms_method_key_list_push(&program->deferred_index,
                          (MsMethodKey){.key = node_key(module, node), .entry = (uint32_t)program->deferred_bodies.len - 1});
}

static void defer_function(MsCheckProgram *program, uint32_t module, MsDecl *decl, MsMethod *method) {
  MsFunc *func = method != NULL ? &method->func : &decl->u.fn;
  const uint32_t node = method != NULL ? method->id : decl->id;
  if ((func->body.len == 0 && func->lazy.end == 0) || func->external || func->bodiless) {
    if (has_default(func->params)) {
      list_defaults(program, module, node, decl, method);
    }
    return;
  }
  ms_deferred_body_list_push(&program->deferred_bodies,
                             (MsDeferredBody){.module = module, .node = node, .decl = decl, .method = method, .body = func->body});
  ms_method_key_list_push(&program->deferred_index,
                          (MsMethodKey){.key = node_key(module, node), .entry = (uint32_t)program->deferred_bodies.len - 1});
  func->body = (MsStmts){0};
  func->deferred = true;
}

void ms_check_defer_std_bodies(MsCheckProgram *program) {
  for (uint32_t module = program->user_modules; module < program->modules.len; module++) {
    const MsModule *tree = program->modules.ptr[module].tree;
    for (uint32_t index = 0; index < tree->ndecls; index++) {
      MsDecl *decl = (MsDecl *)(void *)tree->decls[index];
      if (decl->kind == MS_D_FN) {
        defer_function(program, module, decl, NULL);
      }
      if (decl->kind == MS_D_TYPE && has_default(decl->u.type.fields)) {
        list_defaults(program, module, decl->id, decl, NULL);
      }
      for (uint32_t at = 0; decl->kind == MS_D_IMPL && at < decl->u.impl.methods.len; at++) {
        defer_function(program, module, decl, decl->u.impl.methods.ptr[at]);
      }
    }
  }
  ms_sort((uint8_t *)program->deferred_index.ptr, program->deferred_index.len, sizeof(MsMethodKey), compare_keys, NULL);
}

enum { HOOK_COUNT = 24 }; /* at least the entries of MS_HOOK_METHODS */

/* A hook method (hooks.h) by the head of its receiver type: the head is what ms_check_method_targets compares
 * (see its same_head), so one lookup per type replaces a scan of the methods named by each hook. */
typedef struct HookTarget {
  uint64_t head;
  uint32_t module, node;
} HookTarget;

MS_LIST_DEFINE(HookTargetList, hook_target_list, HookTarget)

enum { HEAD_ANY = 0 }; /* a receiver that is a type variable fits every type */

typedef struct Reach {
  MsCheckProgram *program;
  MsDeferredBodyList *queue;  /* indices of the bodies restored and not yet scanned */
  uint32_t module;            /* the module whose facts the walk reads */
  uint8_t *typed;             /* per type id: its hook methods were restored */
  size_t typed_len;
  size_t bindings;            /* the bindings of the program already read */
  MsName hooks[HOOK_COUNT];   /* the hook names (hooks.h) some deferred method has; the rest need no lookup */
  size_t hook_count;
  HookTargetList targets;     /* the methods of those names by receiver head, sorted by head */
  bool any_done;              /* the methods with a type-variable receiver were restored */
} Reach;

/* The head of a type: its definition, or else its kind and builtin. Definitions are aligned, so the low bit tells the
 * two apart. */
static uint64_t head_of(const MsCheckProgram *program, MsTy ty) {
  const MsDef *def = ms_check_def_of(program, ty);
  if (def != NULL) {
    return (uint64_t)(uintptr_t)def;
  }
  return 1u | (uint64_t)ms_ty_kind(&program->types, ty) << 8 | (uint64_t)ms_ty_builtin(&program->types, ty) << 24;
}

static int64_t compare_targets(uint8_t *env, const uint8_t *left, const uint8_t *right) {
  (void)env;
  const HookTarget *a = (const HookTarget *)(const void *)left;
  const HookTarget *b = (const HookTarget *)(const void *)right;
  return a->head < b->head ? -1 : a->head > b->head;
}

/* Lists the methods that carry a hook name, by receiver head. */
static void index_hook_targets(Reach *reach) {
  const MsCheckProgram *program = reach->program;
  const MsMethodKeyList *named = &program->method_index.by_name;
  for (size_t hook = 0; hook < reach->hook_count; hook++) {
    for (size_t at = 0; at < named->len; at++) {
      if (named->ptr[at].key != reach->hooks[hook]) {
        continue;
      }
      const MsMethodEntry *entry = &program->methods.ptr[named->ptr[at].entry];
      if (entry->source == NULL) {
        continue;
      }
      const bool any = ms_ty_kind(&program->types, entry->receiver) == MS_TY_VARIABLE;
      hook_target_list_push(&reach->targets, (HookTarget){.head = any ? HEAD_ANY : head_of(program, entry->receiver),
                                                          .module = entry->module, .node = entry->source->id});
    }
  }
  ms_sort((uint8_t *)reach->targets.ptr, reach->targets.len, sizeof(HookTarget), compare_targets, NULL);
}

/* Restores the deferred body of the function or method the reference names, and queues it. */
static void reach_node(Reach *reach, uint32_t module, uint32_t node) {
  if (module < reach->program->user_modules || module >= reach->program->modules.len) {
    return;
  }
  const MsMethodKeyList *index = &reach->program->deferred_index;
  const uint64_t key = node_key(module, node);
  size_t low = 0;
  size_t high = index->len;
  while (low < high) {
    const size_t mid = low + (high - low) / 2;
    if (index->ptr[mid].key < key) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  if (low >= index->len || index->ptr[low].key != key) {
    return;
  }
  MsDeferredBody *entry = &reach->program->deferred_bodies.ptr[index->ptr[low].entry];
  if (entry->restored) {
    return;
  }
  entry->restored = true;
  if (!entry->defaults_only) {
    MsFunc *func = entry->method != NULL ? &entry->method->func : &entry->decl->u.fn;
    func->body = entry->body;
    if (func->lazy.end != 0) {
      MsDiag diag = {0};
      const MsBodyRange range = func->lazy;
      func->lazy = (MsBodyRange){0};
      if (!ms_parse_body(&reach->program->arena, reach->program->names, reach->program->modules.ptr[module].source, range,
                         &func->body, &diag)) {
        ms_fatal(MS_FATAL_INVARIANT, "a bundled standard body does not parse (stale body index)");
      }
      entry->body = func->body;
    }
    func->deferred = false;
  }
  ms_deferred_body_list_push(reach->queue, *entry);
}

/* Restores the hook methods (hooks.h) of `ty` and of the types it is made of: its arguments, fields and cases. A
 * method is found by the head of a type (its definition or builtin), so fields are read as declared, not with the
 * arguments substituted: the walk is finite even for a recursive generic type. */
static void reach_target(void *ctx, uint32_t module, uint32_t node);
static void reach_type(Reach *reach, MsTy ty) {
  MsCheckProgram *program = reach->program;
  if (ty == MS_TY_NONE || ty >= program->types.rows.len) {
    return;
  }
  if (ty >= reach->typed_len) {
    const size_t grown = program->types.rows.len + 64;
    reach->typed = ms_realloc(reach->typed, grown);
    memset(reach->typed + reach->typed_len, 0, grown - reach->typed_len);
    reach->typed_len = grown;
  }
  if (reach->typed[ty] != 0) {
    return;
  }
  reach->typed[ty] = 1;
  if (ms_ty_kind(&program->types, ty) != MS_TY_VARIABLE) {
    const HookTargetList *targets = &reach->targets;
    const uint64_t head = head_of(program, ty);
    size_t low = 0;
    size_t high = targets->len;
    while (low < high) {
      const size_t mid = low + (high - low) / 2;
      if (targets->ptr[mid].head < head) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    for (; low < targets->len && targets->ptr[low].head == head; low++) {
      reach_node(reach, targets->ptr[low].module, targets->ptr[low].node);
    }
    /* The methods with a type-variable receiver (head 0, sorted first) fit every type: restored once. */
    for (size_t at = 0; !reach->any_done && at < targets->len && targets->ptr[at].head == HEAD_ANY; at++) {
      reach_node(reach, targets->ptr[at].module, targets->ptr[at].node);
    }
    reach->any_done = true;
  }
  for (size_t index = 0; index < ms_ty_arg_count(&program->types, ty); index++) {
    reach_type(reach, ms_ty_args(&program->types, ty)[index]);
  }
  const MsDef *def = ms_check_def_of(program, ty);
  for (size_t index = 0; def != NULL && index < def->fields.len; index++) {
    reach_type(reach, def->fields.ptr[index].ty);
  }
  for (size_t index = 0; def != NULL && index < def->cases.len; index++) {
    for (size_t at = 0; at < def->cases.ptr[index].fields.len; at++) {
      reach_type(reach, def->cases.ptr[index].fields.ptr[at].ty);
    }
  }
}

static void reach_ref(Reach *reach, const MsRef *ref) {
  if (ref != NULL && ref->kind != MS_REF_NONE) {
    reach_node(reach, ref->decl.module, ref->decl.node);
  }
}

static void reach_target(void *ctx, uint32_t module, uint32_t node) {
  reach_node(ctx, module, node);
}

static void reach_expr(void *ctx, const MsExpr *expr) {
  Reach *reach = ctx;
  const MsFacts *facts = &reach->program->modules.ptr[reach->module].facts;
  if (expr->id >= facts->node_count) {
    return;
  }
  reach_ref(reach, ms_facts_ref(facts, expr->id));
  if (expr->kind == MS_E_CALL) {
    const MsCall *call = ms_facts_call(facts, expr->id);
    if (call != NULL) {
      reach_ref(reach, &call->callee);
      for (uint32_t at = 0; at < call->type_arg_count; at++) {
        reach_type(reach, call->type_args[at]);
      }
      ms_check_instantiation_targets(reach->program, call, reach_target, reach);
    }
  }
  reach_type(reach, ms_facts_type(facts, expr->id));
  const MsConversion *conversion = ms_facts_conversion(facts, expr->id);
  if (conversion != NULL && conversion->kind == MS_CONV_INTERFACE_VIEW) {
    ms_check_view_targets(reach->program, conversion, reach_target, reach);
  }
}

static void scan_decl(Reach *reach, uint32_t module, const MsDecl *decl) {
  reach->module = module;
  ms_walk_decl(&(MsVisitor){.ctx = reach, .expr = reach_expr}, decl);
}

void ms_check_restore_reached(MsCheckProgram *program) {
  MsDeferredBodyList queue = {0};
  Reach reach = {.program = program, .queue = &queue};
  for (int hook = 0; hook < MS_HOOK_COUNT; hook++) {
    MsName name = MS_NAME_EMPTY;
    if (!ms_names_find(program->names, ms_span_of_text(ms_hook_name((MsHook)hook)), &name)) {
      continue;
    }
    for (size_t at = 0; at < program->deferred_bodies.len; at++) {
      const MsDeferredBody *entry = &program->deferred_bodies.ptr[at];
      if (entry->method != NULL && entry->method->func.name == name) {
        reach.hooks[reach.hook_count++] = name;
        break;
      }
    }
  }
  index_hook_targets(&reach);
  for (uint32_t module = 0; module < program->user_modules; module++) {
    const MsModule *tree = program->modules.ptr[module].tree;
    for (uint32_t index = 0; index < tree->ndecls; index++) {
      scan_decl(&reach, module, tree->decls[index]);
    }
  }
  const char *const roots[] = {
#define MS_HOOK_ITEM(text) text,
      MS_ROOT_FUNCTIONS(MS_HOOK_ITEM)
#undef MS_HOOK_ITEM
  };
  for (size_t index = 0; index < program->deferred_bodies.len; index++) {
    const MsDeferredBody *entry = &program->deferred_bodies.ptr[index];
    if (entry->method != NULL) {
      continue;
    }
    for (size_t at = 0; at < sizeof roots / sizeof roots[0]; at++) {
      if (ms_span_is_text(ms_names_span(program->names, entry->decl->u.fn.name), roots[at])) {
        reach_node(&reach, entry->module, entry->node);
      }
    }
  }
  do {
    while (queue.len > 0) {
      MsDeferredBody entry = queue.ptr[queue.len - 1];
      queue.len--;
      reach.module = entry.module;
      if (entry.decl->kind == MS_D_TYPE) {
        ms_walk_decl(&(MsVisitor){.ctx = &reach, .expr = reach_expr}, entry.decl);
        continue;
      }
      if (!entry.defaults_only) {
        ms_check_deferred_body(program, entry.module, entry.decl, entry.method);
      }
      const MsFunc *func = entry.method != NULL ? &entry.method->func : &entry.decl->u.fn;
      ms_walk_callable(&(MsVisitor){.ctx = &reach, .expr = reach_expr}, func->params, func->body);
    }
    /* A binding or parameter of a type is closed where its scope ends: no expression need name the type. */
    for (; reach.bindings < program->bindings.len; reach.bindings++) {
      reach_type(&reach, program->bindings.ptr[reach.bindings].ty);
    }
  } while (queue.len > 0);
  ms_free(reach.typed);
  hook_target_list_free(&reach.targets);
  ms_deferred_body_list_free(&queue);
}

void ms_check_lazy_std_free(MsCheckProgram *program) {
  ms_deferred_body_list_free(&program->deferred_bodies);
  ms_method_key_list_free(&program->deferred_index);
}

/* compiler/check/lazy_std.c: checks the bodies of bundled standard functions only when something reaches them.
 *
 * The bundled standard library is fixed per binary and `ms check stdlib` checks all of it, so a run that only
 * analyzes a program (check, lint, the language server) needs the bodies of the standard functions its code can
 * reach, not every one the prelude defines: the ownership masks of a callee come from its body, the rest of the
 * prelude's bodies change no diagnostic of the program. The bodies are set aside (blank) before the body walk, and
 * every function or method a checked body names is given its body back and checked, until nothing new is named.
 * Lowering never runs on such a program (`program->lazy_std` is set only by the analysis commands). */
#include "base/sort.h"
#include "compiler/check/body.h"
#include "compiler/check/dispatch_targets.h"
#include "compiler/check/lazy_std.h"
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

static void defer_function(MsCheckProgram *program, uint32_t module, MsDecl *decl, MsMethod *method) {
  MsFunc *func = method != NULL ? &method->func : &decl->u.fn;
  if (func->body.len == 0 || func->external || func->bodiless) {
    return;
  }
  const uint32_t node = method != NULL ? method->id : decl->id;
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
      for (uint32_t at = 0; decl->kind == MS_D_IMPL && at < decl->u.impl.methods.len; at++) {
        defer_function(program, module, decl, decl->u.impl.methods.ptr[at]);
      }
    }
  }
  ms_sort((uint8_t *)program->deferred_index.ptr, program->deferred_index.len, sizeof(MsMethodKey), compare_keys, NULL);
}

typedef struct Reach {
  MsCheckProgram *program;
  MsDeferredBodyList *queue;  /* indices of the bodies restored and not yet scanned */
  uint32_t module;            /* the module whose facts the walk reads */
} Reach;

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
  MsFunc *func = entry->method != NULL ? &entry->method->func : &entry->decl->u.fn;
  func->body = entry->body;
  func->deferred = false;
  ms_deferred_body_list_push(reach->queue, *entry);
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
      ms_check_instantiation_targets(reach->program, call, reach_target, reach);
    }
  }
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
  for (uint32_t module = 0; module < program->user_modules; module++) {
    const MsModule *tree = program->modules.ptr[module].tree;
    for (uint32_t index = 0; index < tree->ndecls; index++) {
      scan_decl(&reach, module, tree->decls[index]);
    }
  }
  while (queue.len > 0) {
    MsDeferredBody entry = queue.ptr[queue.len - 1];
    queue.len--;
    ms_check_deferred_body(program, entry.module, entry.decl, entry.method);
    reach.module = entry.module;
    const MsFunc *func = entry.method != NULL ? &entry.method->func : &entry.decl->u.fn;
    ms_walk_callable(&(MsVisitor){.ctx = &reach, .expr = reach_expr}, func->params, func->body);
  }
  ms_deferred_body_list_free(&queue);
}

void ms_check_lazy_std_free(MsCheckProgram *program) {
  ms_deferred_body_list_free(&program->deferred_bodies);
  ms_method_key_list_free(&program->deferred_index);
}

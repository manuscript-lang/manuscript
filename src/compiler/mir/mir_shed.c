/* shed: removes the cleanup entries that only free memory from a program that cannot survive a fault.
 *
 * A fault in a program that starts no task ends the process, so a cleanup entry whose closer is a plain
 * `close.drop.N` (free the value in a slot) runs to no effect. Each such entry still keeps its slot in memory,
 * because the runtime holds the slot's address: a list that a loop pushes onto reloads and stores its header on
 * every push. Entries that close a resource (a file, a user `close`) stay.
 *
 * The handle a push returns reaches `msrt_cleanup_discard`/`cancel` calls and travels through block parameters.
 * A function is rewritten when every use of every such handle is one of those two, directly or through a
 * parameter that only handles reach; the pushes, those calls and those parameters then go. Any other use leaves
 * the function as it is. */

#include "compiler/mir/mir_shed.h"

#include "compiler/mir/mir_analysis.h"
#include "compiler/mir/mir_pass.h"

static bool shed_drop_closer(const MirModule *m, const MirInst *inst) {
  static const char prefix[] = "close.drop.";
  if (inst->op != MOP_CleanupPush || inst->imm.tag != MI_FUNC || inst->res == MIR_NONE) {
    return false;
  }
  const MsSpan name = ms_names_span(&m->names, m->funcs.ptr[inst->imm.a].name);
  return name.len > sizeof prefix - 1 && __builtin_memcmp(name.ptr, prefix, sizeof prefix - 1) == 0;
}

static bool shed_retires(const MirModule *m, const MirInst *inst) {
  if (inst->op != MOP_CallRt || inst->imm.tag != MI_EXT || inst->nargs != 1) {
    return false;
  }
  const uint8_t role = m->externs.ptr[inst->imm.a].role;
  return role == MR_CLEANUP_DISCARD || role == MR_CLEANUP_CANCEL;
}

/* The block parameter an edge's `index`-th argument lands on. */
static MirValue shed_param(const MirFunc *f, const MirTarget *target, uint32_t index) {
  return f->blocks.ptr[target->block].params.ptr[index].value;
}

/* Marks the handles of `f` and says whether every use of them can go. */
static bool shed_taint(const MirModule *m, const MirFunc *f, MirBits *tainted, bool *any) {
  *any = false;
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
      const MirInst *inst = &f->blocks.ptr[b].insts.ptr[i];
      if (shed_drop_closer(m, inst)) {
        mir_bits_set(tainted, inst->res);
        *any = true;
      }
    }
  }
  if (!*any) {
    return false;
  }
  for (bool changed = true; changed;) { /* a parameter fed by a handle is a handle */
    changed = false;
    for (uint32_t b = 0; b < f->blocks.len; b++) {
      MirTerm term = f->blocks.ptr[b].term;
      for (uint32_t t = 0; t < mir_term_ntargets(&term); t++) {
        const MirTarget *target = mir_term_target(&term, t);
        for (uint32_t a = 0; a < target->nargs; a++) {
          const MirValue param = shed_param(f, target, a);
          if (mir_bits_test(tainted, target->args[a]) && !mir_bits_test(tainted, param)) {
            mir_bits_set(tainted, param);
            changed = true;
          }
        }
      }
    }
  }
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    const MirBlockData *block = &f->blocks.ptr[b];
    for (uint32_t i = 0; i < block->insts.len; i++) {
      const MirInst *inst = &block->insts.ptr[i];
      for (uint32_t a = 0; a < inst->nargs; a++) {
        if (mir_bits_test(tainted, inst->args[a]) && !(a == 0 && shed_retires(m, inst))) {
          return false;
        }
      }
    }
    MirTerm term = block->term;
    if (term.value != MIR_NONE && mir_bits_test(tainted, term.value)) {
      return false;
    }
    for (uint32_t t = 0; t < mir_term_ntargets(&term); t++) {
      const MirTarget *target = mir_term_target(&term, t);
      for (uint32_t a = 0; a < target->nargs; a++) {
        if (mir_bits_test(tainted, target->args[a]) != mir_bits_test(tainted, shed_param(f, target, a))) {
          return false; /* a parameter that handles share with other values */
        }
      }
    }
  }
  return true;
}

static void shed_function(MirModule *m, MirFunc *f, const MirBits *tainted) {
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    MirBlockData *block = &f->blocks.ptr[b];
    uint32_t *dead = MS_ARENA_NEW_ARRAY(&m->arena, uint32_t, block->insts.len + 1);
    uint32_t ndead = 0;
    for (uint32_t i = 0; i < block->insts.len; i++) {
      const MirInst *inst = &block->insts.ptr[i];
      const bool push = inst->op == MOP_CleanupPush && inst->res != MIR_NONE && mir_bits_test(tainted, inst->res);
      if (push || (shed_retires(m, inst) && mir_bits_test(tainted, inst->args[0]))) {
        dead[ndead++] = i;
      }
    }
    mir_block_remove(block, dead, ndead);
    MirTerm *term = &block->term;
    for (uint32_t t = 0; t < mir_term_ntargets(term); t++) {
      MirTarget *target = mir_term_target(term, t);
      uint32_t kept = 0;
      for (uint32_t a = 0; a < target->nargs; a++) {
        if (!mir_bits_test(tainted, shed_param(f, target, a))) {
          target->args[kept++] = target->args[a];
        }
      }
      target->nargs = kept;
    }
  }
  for (uint32_t b = 0; b < f->blocks.len; b++) {
    MirBlockParamList *params = &f->blocks.ptr[b].params;
    uint32_t kept = 0;
    for (uint32_t p = 0; p < params->len; p++) {
      if (!mir_bits_test(tainted, params->ptr[p].value)) {
        params->ptr[kept++] = params->ptr[p];
      }
    }
    params->len = kept;
  }
}

bool mir_shed(MirModule *m) {
  if (mir_starts_tasks(m)) {
    return false;
  }
  MsArena arena = ms_arena_new();
  bool changed = false;
  for (uint32_t fi = 0; fi < m->funcs.len; fi++) {
    MirFunc *f = &m->funcs.ptr[fi];
    if (f->blocks.len == 0) {
      continue;
    }
    MirBits tainted = mir_bits_new(&arena, (uint32_t)f->values.len + 1);
    bool any = false;
    if (shed_taint(m, f, &tainted, &any) && any) {
      shed_function(m, f, &tainted);
      changed = true;
    }
  }
  ms_arena_free(&arena);
  return changed;
}

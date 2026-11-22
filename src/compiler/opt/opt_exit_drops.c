/* The `exit_drops` pass: the program entry returns to a process that is about to exit, so the drops of plain
 * memory on its return paths (a map of types, a list of strings) only walk and free memory the operating
 * system takes back. Each such drop runs only when `msrt_exit_frees` says so: the counting runtime that
 * `make leak-check` links and `MS_FREE_AT_EXIT=1` (for valgrind) keep them. Resources still close: a closer is
 * a call, and a closure, an interface value or a runtime handle is never skipped (`mir_drops_plain_memory`). */
#include "compiler/opt/opt_pass.h"

/* Instructions that may sit between the exit drops and the return. */
static bool is_exit_tail(uint8_t op) {
  return op == MOP_Drop || op == MOP_DropIf || op == MOP_DepthLeave || op == MOP_IConst || op == MOP_BConst ||
         op == MOP_VoidConst;
}

/* One returning path: where its run of exit drops starts and which of them are plain. */
typedef struct ExitPath {
  uint32_t block, start;
  bool *plain;
} ExitPath;

/* Whether the block ends the process-exit path: it returns, or jumps to a block that only builds the result and
 * returns (what inlining `main` into the entry leaves). */
static bool exits_process(const MirFunc *f, const MirBlockData *b) {
  if (b->term.kind == MT_RET) {
    return true;
  }
  if (b->term.kind != MT_BR) {
    return false;
  }
  const MirBlockData *c = &f->blocks.ptr[b->term.a.block];
  if (c->term.kind != MT_RET) {
    return false;
  }
  for (uint32_t i = 0; i < c->insts.len; i++) {
    if (!is_exit_tail(c->insts.ptr[i].op)) {
      return false;
    }
  }
  return true;
}

/* The paths of `f` that end in at least one plain drop. */
static uint32_t plan_paths(MsArena *arena, const MirModule *m, const MirFunc *f, ExitPath **out) {
  ExitPath *paths = MS_ARENA_NEW_ARRAY(arena, ExitPath, f->blocks.len + 1);
  uint32_t count = 0;
  for (uint32_t bi = 0; bi < f->blocks.len; bi++) {
    const MirBlockData *b = &f->blocks.ptr[bi];
    if (!exits_process(f, b)) {
      continue;
    }
    uint32_t start = (uint32_t)b->insts.len;
    while (start > 0 && is_exit_tail(b->insts.ptr[start - 1].op)) {
      start--;
    }
    bool *plain = MS_ARENA_NEW_ARRAY(arena, bool, (b->insts.len - start) + 1);
    bool any = false;
    for (uint32_t i = start; i < b->insts.len; i++) {
      const MirInst *inst = &b->insts.ptr[i];
      plain[i - start] = inst->op == MOP_Drop && mir_drops_plain_memory(m, f->values.ptr[inst->args[0]]);
      any |= plain[i - start];
    }
    if (any) {
      paths[count++] = (ExitPath){bi, start, plain};
    }
  }
  *out = paths;
  return count;
}

/* Rewrites the plain drops of one path to `drop.if` on the result of the gate call, placed before them. */
static void gate_path(MirModule *m, MirFunc *f, const ExitPath *path, uint32_t gate) {
  MirBlockData *b = &f->blocks.ptr[path->block];
  const uint32_t len = (uint32_t)b->insts.len;
  const MirLoc loc = b->insts.ptr[path->start].loc;
  MirInstList out = {0};
  for (uint32_t i = 0; i < path->start; i++) {
    mir_inst_list_push(&out, b->insts.ptr[i]);
  }
  const MirValue flag = mir_new_value(f, MIR_BOOL);
  mir_inst_list_push(&out, mir_inst(MOP_CallRt, mir_imm_ext(gate), flag, loc, mir_args_copy(m, NULL, 0), 0));
  for (uint32_t i = path->start; i < len; i++) {
    MirInst inst = b->insts.ptr[i];
    if (path->plain[i - path->start]) {
      const MirValue args[2] = {flag, inst.args[0]};
      inst.op = MOP_DropIf;
      inst.args = mir_args_copy(m, args, 2);
      inst.nargs = 2;
    }
    mir_inst_list_push(&out, inst);
  }
  mir_block_set_insts(b, &out);
}

/* Gates the plain drops that end each returning path of function `fid`. */
static bool gate_returns(MirModule *m, uint32_t fid, uint32_t *gate) {
  MsArena arena = ms_arena_new();
  ExitPath *paths = NULL;
  const uint32_t count = plan_paths(&arena, m, &m->funcs.ptr[fid], &paths);
  if (count > 0 && *gate == MIR_NONE) {
    *gate = mir_extern_get(m, ms_span_of_text("msrt_exit_frees"), NULL, 0, MIR_BOOL, true, MR_NONE);
  }
  for (uint32_t k = 0; k < count; k++) {
    gate_path(m, &m->funcs.ptr[fid], &paths[k], *gate);
  }
  ms_arena_free(&arena);
  return count > 0;
}

/* Gates the exit drops of the entry, and of a `main` it calls once; run after the passes that need to see every
 * `drop` (`copyelim`, `simplify`) and before `lastuse`. An entry that something calls again, or a `main` called
 * from anywhere but the entry, is left alone: its return is not the process exit. */
bool opt_exit_drops(MirModule *m) {
  if (m->entry == MIR_NONE) {
    return false;
  }
  const uint32_t nfuncs = (uint32_t)m->funcs.len;
  uint32_t *ncalls = MS_ARENA_NEW_ARRAY(&m->arena, uint32_t, (size_t)nfuncs + 1);
  uint32_t *caller = MS_ARENA_NEW_ARRAY(&m->arena, uint32_t, (size_t)nfuncs + 1);
  for (uint32_t fi = 0; fi < nfuncs; fi++) {
    const MirFunc *f = &m->funcs.ptr[fi];
    for (uint32_t b = 0; b < f->blocks.len; b++) {
      for (uint32_t i = 0; i < f->blocks.ptr[b].insts.len; i++) {
        const MirInst *inst = &f->blocks.ptr[b].insts.ptr[i];
        if (inst->op == MOP_Call && inst->imm.tag == MI_FUNC) {
          ncalls[inst->imm.a]++;
          caller[inst->imm.a] = fi;
        }
      }
    }
  }
  uint32_t gate = MIR_NONE;
  bool changed = false;
  const uint32_t entry = m->entry;
  if (ncalls[entry] == 0) {
    changed |= gate_returns(m, entry, &gate);
  }
  for (uint32_t gi = 0; gi < nfuncs; gi++) {
    if (gi != entry && mir_name_is(m, m->funcs.ptr[gi].name, "main") && ncalls[gi] == 1 && caller[gi] == entry) {
      changed |= gate_returns(m, gi, &gate);
    }
  }
  return changed;
}

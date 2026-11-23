/* compiler/check/order.c: the order diagnostics are listed in (see order.h). */
#include "compiler/check/order.h"

#include "base/sort.h"

/* The position of a declaration among its module's, counting from 1; 0 for what precedes the first (imports). */
static uint32_t declaration_of(const MsCheckProgram *program, const MsCheckDiag *diag) {
  const MsModule *tree = program->modules.ptr[diag->module].tree;
  uint32_t found = 0;
  for (uint32_t index = 0; index < tree->ndecls; index++) {
    if (tree->decls[index]->pos.offset <= diag->pos.offset) {
      found = index + 1;
    }
  }
  return found;
}

static bool in_body(const MsCheckDiag *diag) {
  return diag->stage == MS_STAGE_SIDE || diag->stage == MS_STAGE_WALK;
}

/* Imports are bound before anything is declared; declarations come next, then bodies. */
static int64_t stage_rank(const MsCheckDiag *diag) {
  if (diag->stage == MS_STAGE_IMPORTS) {
    return -1;
  }
  return in_body(diag) ? 1 : 0;
}

static int64_t compare(uint8_t *env, const uint8_t *left, const uint8_t *right) {
  const MsCheckProgram *program = (const MsCheckProgram *)__builtin_assume_aligned(env, _Alignof(MsCheckProgram));
  const MsCheckDiag *a = (const MsCheckDiag *)__builtin_assume_aligned(left, _Alignof(MsCheckDiag));
  const MsCheckDiag *b = (const MsCheckDiag *)__builtin_assume_aligned(right, _Alignof(MsCheckDiag));
  if (a->module != b->module) {
    return (int64_t)a->module - (int64_t)b->module;
  }
  if (stage_rank(a) != stage_rank(b)) {
    return stage_rank(a) - stage_rank(b);
  }
  if (!in_body(a)) {
    return 0; /* the passes before bodies already run in the oracle's order */
  }
  const int64_t decl = (int64_t)declaration_of(program, a) - (int64_t)declaration_of(program, b);
  if (decl != 0) {
    return decl;
  }
  return a->ends_decl == b->ends_decl ? 0 : (a->ends_decl ? 1 : -1);
}

static uint32_t slot(const MsCheckDiag *diag) {
  return diag->anchor != 0 ? diag->anchor : diag->pos.offset;
}

static int64_t by_position(uint8_t *env, const uint8_t *left, const uint8_t *right) {
  (void)env;
  const MsCheckDiag *a = (const MsCheckDiag *)__builtin_assume_aligned(left, _Alignof(MsCheckDiag));
  const MsCheckDiag *b = (const MsCheckDiag *)__builtin_assume_aligned(right, _Alignof(MsCheckDiag));
  return (int64_t)slot(a) - (int64_t)slot(b);
}

/* Within one declaration's body diagnostics, the body walk's own order is kept and what the side passes found is
 * slipped in by position: before the first walk diagnostic that lies after it. */
static void merge_group(MsCheckDiag *group, size_t count) {
  MsCheckDiagList side = {0};
  MsCheckDiagList walk = {0};
  for (size_t index = 0; index < count; index++) {
    ms_check_diag_list_push(group[index].stage == MS_STAGE_SIDE ? &side : &walk, group[index]);
  }
  ms_sort((uint8_t *)side.ptr, side.len, sizeof(MsCheckDiag), by_position, NULL);
  size_t next = 0;
  size_t at = 0;
  for (size_t index = 0; index < walk.len; index++) {
    while (next < side.len && slot(&side.ptr[next]) < walk.ptr[index].pos.offset) {
      group[at++] = side.ptr[next++];
    }
    group[at++] = walk.ptr[index];
  }
  while (next < side.len) {
    group[at++] = side.ptr[next++];
  }
  ms_check_diag_list_free(&side);
  ms_check_diag_list_free(&walk);
}

void ms_check_order_diagnostics(MsCheckProgram *program) {
  MsCheckDiag *all = program->diagnostics.ptr;
  const size_t total = program->diagnostics.len;
  ms_sort((uint8_t *)all, total, sizeof(MsCheckDiag), compare, (uint8_t *)program);
  size_t start = 0;
  while (start < total) {
    size_t end = start + 1;
    while (end < total && compare((uint8_t *)program, (const uint8_t *)&all[start], (const uint8_t *)&all[end]) == 0) {
      end++;
    }
    if (in_body(&all[start]) && !all[start].ends_decl) {
      merge_group(all + start, end - start);
    }
    start = end;
  }
}

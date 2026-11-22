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

static int64_t compare(uint8_t *env, const uint8_t *left, const uint8_t *right) {
  const MsCheckProgram *program = (const MsCheckProgram *)__builtin_assume_aligned(env, _Alignof(MsCheckProgram));
  const MsCheckDiag *a = (const MsCheckDiag *)__builtin_assume_aligned(left, _Alignof(MsCheckDiag));
  const MsCheckDiag *b = (const MsCheckDiag *)__builtin_assume_aligned(right, _Alignof(MsCheckDiag));
  if (a->module != b->module) {
    return (int64_t)a->module - (int64_t)b->module;
  }
  const int64_t decl = (int64_t)declaration_of(program, a) - (int64_t)declaration_of(program, b);
  if (decl != 0) {
    return decl;
  }
  if (a->ends_decl != b->ends_decl) {
    return a->ends_decl ? 1 : -1;
  }
  return a->ends_decl ? 0 : (int64_t)a->pos.offset - (int64_t)b->pos.offset;
}

void ms_check_order_diagnostics(MsCheckProgram *program) {
  ms_sort((uint8_t *)program->diagnostics.ptr, program->diagnostics.len, sizeof(MsCheckDiag), compare,
          (uint8_t *)program);
}

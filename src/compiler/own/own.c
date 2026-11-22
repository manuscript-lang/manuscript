/* compiler/own/own.c: the entry point of the ownership check. */
#include "compiler/own/own.h"

#include "compiler/own/borrows.h"
#include "compiler/own/changes.h"
#include "compiler/own/closers.h"
#include "compiler/own/escapes.h"
#include "compiler/own/result_borrows.h"
#include "compiler/own/moves.h"
#include "compiler/own/taken.h"
#include "compiler/own/unused.h"
#include "compiler/own/uses.h"

void ms_own_check(MsCheckProgram *program) {
  const bool checked_clean = program->diagnostics.len == 0; /* an unresolved name leaves its uses unknown */
  ms_own_uses(program);
  for (int round = 0; round < 4 && ms_own_taken(program); round++) { /* a taken parameter moves the caller's argument */
    ms_own_uses(program);
  }
  ms_own_escapes(program);
  ms_own_result_borrows(program);
  ms_own_closers(program);
  ms_own_unused(program);
  ms_own_changes(program);
  ms_own_borrows(program);
  if (checked_clean) {
    ms_own_moves(program);
  }
}

/* compiler/own/own.c: the entry point of the ownership check. */
#include "compiler/own/own.h"

#include "compiler/own/borrows.h"
#include "compiler/own/changes.h"
#include "compiler/own/closers.h"
#include "compiler/own/unused.h"
#include "compiler/own/uses.h"

void ms_own_check(MsCheckProgram *program) {
  ms_own_uses(program);
  ms_own_closers(program);
  ms_own_unused(program);
  ms_own_changes(program);
  ms_own_borrows(program);
}

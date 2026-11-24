/* compiler/own/own.c: the entry point of the ownership check. */
#include "compiler/own/own.h"

#include "compiler/own/borrows.h"
#include "compiler/own/changes.h"
#include "compiler/own/closers.h"
#include "compiler/own/escapes.h"
#include "compiler/own/result_borrows.h"
#include "compiler/own/moves.h"
#include "compiler/own/overlaps.h"
#include "compiler/own/relays.h"
#include "compiler/own/taken.h"
#include "compiler/own/unused.h"
#include "compiler/own/uses.h"

void ms_own_check(MsCheckProgram *program) {
  const bool checked_clean = program->diagnostics.len == 0; /* an unresolved name leaves its uses unknown */
  if (checked_clean) {
    for (size_t at = 0; at < program->ownership.len; at++) {
      ms_check_diag_list_push(&program->diagnostics, program->ownership.ptr[at]);
    }
  }
  MsUsesSeen *seen = NULL;
  ms_own_uses(program, &seen);
  for (int round = 0; round < 4 && ms_own_taken(program); round++) { /* a taken parameter moves the caller's argument */
    ms_own_uses(program, &seen);
  }
  ms_own_escapes(program);
  ms_own_uses(program, &seen); /* a parameter an escaping closure keeps is taken now: its callers' arguments move */
  ms_own_uses_seen_free(seen);
  ms_own_result_borrows(program);
  if (checked_clean) {
    ms_own_mixed_returns(program);
  }
  if (checked_clean) {
    ms_own_taken_report(program);
  }
  ms_own_uses_report(program);
  ms_own_closers(program);
  ms_own_changes(program);
  ms_own_borrows(program);
  if (checked_clean) {
    ms_own_moves(program);
    if (program->diagnostics.len == 0) {
      ms_own_overlaps(program);
    }
    if (program->diagnostics.len == 0) {
      ms_own_relays(program);
    }
  }
  ms_own_unused(program); /* a clean program only: any other diagnostic leaves unread bindings unreported */
}

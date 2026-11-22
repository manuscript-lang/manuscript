/* compiler/check/drop_labels.h: `ms fmt --drop-labels`. Port of crates/ms-tooling/src/labels.rs. */
#ifndef MS_COMPILER_CHECK_DROP_LABELS_H
#define MS_COMPILER_CHECK_DROP_LABELS_H

#include "compiler/check/program.h"

/* Removes `name:` from an argument written `name: name` when the call binds the same parameter without it. An
 * unlabeled argument fills the first parameter no earlier argument supplied, so a label goes only where that
 * parameter is the labeled one. `module` is a module of the checked `program` and `source` its text. Returns the
 * edited text in `arena`, or `source` itself when nothing changes. The program must have no diagnostics. */
MsSpan ms_drop_redundant_labels(MsArena *arena, const MsCheckProgram *program, uint32_t module, MsSpan source);

#endif

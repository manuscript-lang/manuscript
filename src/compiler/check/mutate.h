/* compiler/check/mutate.h: the mutability pass, assignments to names that cannot be assigned.
 *
 * A syntax-only walk with lexical scopes: an assignment to a binding declared without `var` reports "cannot
 * assign immutable binding" with an edit that rewrites the declaration to `var`; an assignment to a
 * declaration of the module (a constant, function or type) reports that it is not a binding. A name found
 * nowhere is left to the name checker. */
#ifndef MS_COMPILER_CHECK_MUTATE_H
#define MS_COMPILER_CHECK_MUTATE_H

#include "compiler/check/program.h"

/* Checks module `module`, whose source text is `source`, and reports through ms_check_report in the type
 * phase. */
void ms_check_mutation(MsCheckProgram *program, uint32_t module, MsSpan source);

#endif

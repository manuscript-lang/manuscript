/* compiler/check/effects_scan.h: the effects scan over a checked program.
 *
 * Builds the callable graph from the checked bodies (a reference to a function, called or used as a value,
 * is an edge; a closure's body belongs to the callable that holds it), reads the effect directives of each
 * callable from its module's source, and resolves which project callables reach an effect no scope permits.
 * Callables are functions, methods, types and constants. A value seen as an interface, and a generic function called at a
 * concrete type, reach the methods the interface or the bound names.
 *
 * Ownership: the result lives in `arena`; the program must outlive it. */
#ifndef MS_COMPILER_CHECK_EFFECTS_SCAN_H
#define MS_COMPILER_CHECK_EFFECTS_SCAN_H

#include "compiler/check/effects_reach.h"
#include "compiler/check/program.h"

/* Runs the scan after ms_check_graph. */
MsReach ms_check_effects(const MsCheckProgram *program, MsArena *arena);

/* The text of one violation as `ms check --only lint` words it, without file position: "`f` reaches e: f -> g; ...". */
void ms_effect_message(MsStrBuild *out, MsSpan label, const MsReachViolation *violation);

#endif

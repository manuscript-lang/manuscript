/* compiler/check/dispatch_targets.h: the methods a checked expression can run without naming them.
 *
 * A value seen as an interface runs the methods of its type that the interface's operations name; a generic
 * function called at a concrete type runs the methods its bounds name on that type, and drops values of its type
 * arguments, which runs their `close`. The effects scan reads these as edges and the lazy standard checker as
 * bodies to restore.
 *
 * Ownership: nothing is allocated; `visit` gets each method's module and node. */
#ifndef MS_COMPILER_CHECK_DISPATCH_TARGETS_H
#define MS_COMPILER_CHECK_DISPATCH_TARGETS_H

#include "compiler/check/facts.h"
#include "compiler/check/program.h"

typedef void (*MsTargetFn)(void *ctx, uint32_t module, uint32_t node);

/* The methods named `name` that can run for a value of type `ty` (declared on its definition, or on its builtin). */
void ms_check_method_targets(const MsCheckProgram *program, MsTy ty, MsName name, MsTargetFn visit, void *ctx);

/* The methods of `conversion->from` that the interface `conversion->to` names. */
void ms_check_view_targets(const MsCheckProgram *program, const MsConversion *conversion, MsTargetFn visit, void *ctx);

/* The methods a call's type arguments run: through the callee's bounds, and their `close`. */
void ms_check_instantiation_targets(const MsCheckProgram *program, const MsCall *call, MsTargetFn visit, void *ctx);

#endif

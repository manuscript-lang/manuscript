/* compiler/own/taken.h: the resource parameters a body takes. A parameter not declared `move` whose body hands it on
 * (returns it, stores it, binds it) is the callee's to own, and the caller hands it over instead of lending it. The
 * `taken` fact holds one bit per parameter for each function and method declaration. */
#ifndef MS_COMPILER_OWN_TAKEN_H
#define MS_COMPILER_OWN_TAKEN_H

#include <stdbool.h>

#include "compiler/check/program.h"

/* Recomputes the masks of every user module; true when one changed. */
bool ms_own_taken(MsCheckProgram *program);

/* The mask of the function or method declared by `node` of `module`: bit i is the i-th parameter, the receiver
 * not counted. */
uint32_t ms_own_taken_mask(const MsCheckProgram *program, uint32_t module, MsNode node);

/* Whether argument `index` of `call` (receiver first for a method) is a parameter its callee takes. */
bool ms_own_call_takes(const MsCheckProgram *program, const MsCall *call, uint32_t index);

#endif

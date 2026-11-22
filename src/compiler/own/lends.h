/* compiler/own/lends.h: which parameters a callable's result lends.
 *
 * A callable lends a parameter when every value it returns is that parameter or a part of it (through `?`, a case
 * wrapper such as `ok(part)`, or a callable that itself lends), so the caller keeps owning the memory and the
 * result is a borrow, not a copy. A single path that returns something new, a local, or a literal makes the
 * callable an owner: its mask is 0. The `lends` fact holds one bit per position for each function and method
 * declaration of every module, computed as a least fixpoint, so a self-recursive `return f(x)` lends nothing by
 * itself. Positions: a method's receiver is 0 and its parameters follow; a function's parameters start at 0. */
#ifndef MS_COMPILER_OWN_LENDS_H
#define MS_COMPILER_OWN_LENDS_H

#include <stdbool.h>

#include "compiler/check/program.h"

/* Bit 31 of the mask: every path of the callable returns a borrowed part (or nothing that owns memory), so its
 * result can be returned without a copy and callers bind it as a borrow (`ret_borrowed`). The position bits below it
 * are the union over all paths, which is what the borrow check needs: a path that returns something new does not
 * make the other paths safe to ignore. */
#define MS_LENDS_PURE UINT32_C(0x80000000)

/* Recomputes the masks of every module. */
void ms_own_lends(MsCheckProgram *program);

/* The mask of the function or method declared by `node` of `module`. */
uint32_t ms_own_lends_mask(const MsCheckProgram *program, uint32_t module, MsNode node);

/* Whether the callable declared by `node` of `module` has a pure lender result (see MS_LENDS_PURE). */
bool ms_own_lends_pure(const MsCheckProgram *program, uint32_t module, MsNode node);

/* Whether a call's result lends from its argument at `position` (receiver first for a method). A callee the
 * runtime provides lends from every argument that owns memory. */
bool ms_own_call_lends(const MsCheckProgram *program, const MsCall *call, uint32_t position);

/* The function or method a callee ref declares, or NULL when no declaration is found. */
const MsFunc *ms_own_find_func(const MsCheckProgram *program, const MsRef *ref);

#endif

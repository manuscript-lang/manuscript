/* compiler/own/result_borrows.h: which parameters a callable's result borrows.
 *
 * A callable borrows a parameter when every value it returns is that parameter or a part of it (through `?`, a case
 * wrapper such as `ok(part)`, or a callable that itself borrows), so the caller keeps owning the memory and the
 * result is a borrow, not a copy. A single path that returns something new, a local, or a literal makes the
 * callable an owner: its mask is 0. The `borrows` fact holds one bit per position for each function and method
 * declaration of every module, computed as a least fixpoint, so a self-recursive `return f(x)` borrows nothing by
 * itself. Positions: a method's receiver is 0 and its parameters follow; a function's parameters start at 0. */
#ifndef MS_COMPILER_OWN_RESULT_BORROWS_H
#define MS_COMPILER_OWN_RESULT_BORROWS_H

#include <stdbool.h>

#include "compiler/check/program.h"

/* Bit 31 of the mask: every path of the callable returns a borrowed part (or nothing that owns memory), so its
 * result can be returned without a copy and callers bind it as a borrow (`ret_borrowed`). The position bits below it
 * are the union over all paths, which is what the borrow check needs: a path that returns something new does not
 * make the other paths safe to ignore. */
#define MS_RESULT_BORROWED UINT32_C(0x80000000)

/* Recomputes the masks of every module. */
void ms_own_result_borrows(MsCheckProgram *program);

/* Reports each user callable that returns a part of its arguments on one path and a new value on another, and makes
 * its callers see an owner. */
void ms_own_mixed_returns(MsCheckProgram *program);

/* The mask of the function or method declared by `node` of `module`. */
uint32_t ms_own_result_borrow_mask(const MsCheckProgram *program, uint32_t module, MsNode node);

/* Whether the callable declared by `node` of `module` has a pure borrowing callee result (see MS_RESULT_BORROWED). */
/* Whether a function written `&T!` builds its Result on every path (`ok(part)`, `error(e)`, or a call of another such
 * function), so it returns the borrowing variant: the `ok` payload is a part of an argument and the error is owned. */
bool ms_own_returns_variant(const MsCheckProgram *program, uint32_t module, const MsFunc *func);

bool ms_own_result_is_borrowed(const MsCheckProgram *program, uint32_t module, MsNode node);

/* Whether a call's result borrows from its argument at `position` (receiver first for a method). A callee the
 * runtime provides borrows from every argument that owns memory. */
bool ms_own_call_borrows(const MsCheckProgram *program, const MsCall *call, uint32_t position);

/* A runtime read that returns a part of its receiver in place: `xs.get(i)` of a list, `m.get(k)` of a map, `o.get()` of an
 * optional or result. */
typedef enum MsNativeGet { MS_NATIVE_GET_NONE, MS_NATIVE_GET_LIST, MS_NATIVE_GET_MAP, MS_NATIVE_GET_PAYLOAD } MsNativeGet;

MsNativeGet ms_own_native_get(const MsCheckProgram *program, const MsFacts *facts, const MsExpr *call);

/* The function or method a callee ref declares, or NULL when no declaration is found. */
const MsFunc *ms_own_find_func(const MsCheckProgram *program, const MsRef *ref);

#endif

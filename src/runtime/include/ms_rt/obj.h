/* ms_rt/obj.h: objects with a header (closures, handles) and the work counters (src/runtime/core/obj.c). */
#ifndef MS_RT_OBJ_H
#define MS_RT_OBJ_H

#include "ms_rt/base.h"

/* An independent copy of `object` through its clone entry. Null stays null; a value with one owner has no clone entry,
 * and copying it faults (the checker rejects every copy a program could write of one). */
/* ms-sig: msrt_obj_clone(o: *mut Obj) -> *mut Obj */
MsObj *msrt_obj_clone(MsObj *object);
/* Drops an object its owner is done with, running its drop entry. Null is ignored. Past a nesting limit the drop is
 * parked on a list linked through the dead object's clone slot and run when the outermost drop finishes, so long
 * chains (linked lists, deep trees) cannot overflow the stack. */
/* ms-sig: msrt_obj_drop(o: *mut Obj) */
void msrt_obj_drop(MsObj *object);
/* Adds `n` executed MIR operations (a block's instruction count) to the total; `ms bench --ops` builds call it. */
/* ms-sig: msrt_ops_add(n: i64) @leaf */
void msrt_ops_add(int64_t n);
/* Writes the work counters to `out[0..7]`: allocations and their bytes (the calling thread and every finished
 * thread), list copies, list copy bytes, string clones and string clone bytes (the calling isolate), then the MIR
 * operations executed (0 without `--ops`). Counts only grow; a bench reads them before and after a run. */
/* ms-sig: msrt_counts(out: *mut u64) */
void msrt_counts(uint64_t *out);

#endif

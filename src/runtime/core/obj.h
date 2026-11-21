/* Objects with a header (closures, handles): copying and dropping them by exported name, and the bounded drop the
 * runtime installs in base so values that hold objects drop them the same way. */
#ifndef MS_RUNTIME_CORE_OBJ_H
#define MS_RUNTIME_CORE_OBJ_H

#include "base/desc.h"

/* An independent copy of `object` through its clone entry. Null stays null; a value with one owner has no clone
 * entry, and copying it faults (the checker rejects every copy a program could write of one). */
/* ms-sig: msrt_obj_clone(o: *mut Obj) -> *mut Obj */
MsObj *msrt_obj_clone(MsObj *object);
/* Drops an object its owner is done with, running its drop entry. Null is ignored. Past a nesting limit the drop is
 * parked on a list linked through the dead object's clone slot and run when the outermost drop finishes, so long
 * chains (linked lists, deep trees) cannot overflow the stack. */
/* ms-sig: msrt_obj_drop(o: *mut Obj) */
void msrt_obj_drop(MsObj *object);

/* Makes base drop objects through msrt_obj_drop. Called once by the runtime at start-up. */
void ms_obj_install_bounded_drop(void);

#endif

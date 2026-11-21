/* A runtime function that hands its result back through an `out` pointer (`*mut *mut ObjCell<Big>`,
 * `*mut VecVal`) gets room for it in the frame before the call and moves the value out of that room once the
 * call reports success. The two steps sit on either side of the status test, so a caller builds that test
 * between them. */
#include "ms/lower_internal.h"

/* Room for a value of type `ty`, passed to the call as its `out` operand. */
MirValue lo_out_slot(Lb *lb, MirTy ty) {
    return mir_b_emit(&lb->b, MOP_Slot, NULL, 0, (MirImm){.tag = MI_TY, .a = ty}, MIR_PTR);
}

/* The value the call wrote into `slot`, now owned by the caller; emitted only on the path where the call succeeded. */
MirValue lo_take_out(Lb *lb, MirValue slot, MirTy ty) {
    return mir_b_emit(&lb->b, MOP_Take, &slot, 1, (MirImm){.tag = MI_TY, .a = ty}, ty);
}

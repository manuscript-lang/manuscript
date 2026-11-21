/* `StringBuilder` and `BytesBuilder` in the lowering: both are the MIR `bytes` buffer. `Builder()` makes an empty
 * one, `append` and `append_bytes` pass the buffer by address (slot, put, call, take) and write the local back,
 * and `build` consumes it: a `BytesBuilder` is the buffer, a `StringBuilder` freezes it into text. */
#include <string.h>

#include "ms/lower_internal.h"
#include "ms/rt_ops.h"

/* Whether `ty` is the standard `StringBuilder` or `BytesBuilder`. */
bool lbd_is_builder(Lb *lb, MsTy ty) {
    ty = lb_ty(lb, ty);
    if (ms_ty_is(&lb->c->tys, ty, MS_BI_BYTESBUILDER)) {
        return true;
    }
    return ms_ty_kind(&lb->c->tys, ty) == MS_K_NATIVE && lb->c->tys.nargs[ty] == 0 &&
           ms_name_is(lb->c->names, lb->c->tys.name[ty], "StringBuilder");
}

/* `StringBuilder()` or `BytesBuilder()`: an empty buffer. */
LbVal lbd_new(Lb *lb) {
    const MsRtFn *fn = ms_rt_fn_find("msrt_list_new", strlen("msrt_list_new"));
    return fn == NULL ? LB_UNSUPPORTED(lb) : lb_native_call(lb, fn, NULL, 0, MIR_BYTES);
}

static MirValue lbd_slot(Lb *lb) {
    return mir_b_emit(&lb->b, MOP_Slot, NULL, 0, (MirImm){.tag = MI_TY, .a = MIR_BYTES}, MIR_PTR);
}

/* A call of the runtime function `name` on the buffer's slot and `argument` (`MIR_NONE` for none). */
static MirValue lbd_call(Lb *lb, const char *name, MirValue slot, MirValue argument) {
    const MirValue args[2] = {slot, argument};
    const uint32_t count = argument == MIR_NONE ? 1 : 2;
    const MirTy types[2] = {MIR_PTR, argument == MIR_NONE ? MIR_NONE : mir_b_ty(&lb->b, argument)};
    return mir_b_call_rt(&lb->b, lb_runtime_extern(lb, name, types, count, MIR_VOID, MR_NONE, false), args, count);
}

/* `BytesBuilder.append(byte)`: the inline push, else the runtime's growing append. */
static void lbd_push_byte(Lb *lb, MirValue slot, MirValue byte) {
    const MirValue pushed = mir_b_emit(&lb->b, MOP_BytesPush, (const MirValue[]){slot, byte}, 2, (MirImm){0}, MIR_BOOL);
    const MirBlock fast = mir_b_new_block(&lb->b);
    const MirBlock slow = mir_b_new_block(&lb->b);
    const MirBlock join = mir_b_new_block(&lb->b);
    (void)mir_b_add_block_param(&lb->b, join, MIR_VOID, MM_BORROW);
    mir_b_br_if(&lb->b, pushed, fast, NULL, 0, slow, NULL, 0);
    mir_b_seal_block(&lb->b, fast);
    mir_b_switch_to(&lb->b, fast);
    const MirValue done = mir_b_unit(&lb->b);
    mir_b_br(&lb->b, join, &done, 1);
    mir_b_seal_block(&lb->b, slow);
    mir_b_switch_to(&lb->b, slow);
    const MirValue grown = lbd_call(lb, "msrt_bytes_append", slot, byte);
    mir_b_br(&lb->b, join, &grown, 1);
    mir_b_seal_block(&lb->b, join);
    mir_b_switch_to(&lb->b, join);
}

/* `builder.append(x)` or `builder.append_bytes(x)` on a local `var`: the buffer goes through a slot and comes back. */
static LbVal lbd_append(Lb *lb, const MsExpr *e, uint32_t binding, bool text, bool bytes) {
    const LbVal argument = lb_expr(lb, e->u.call.args.ptr[0].value);
    if (!lb->ok) {
        return LB_FAIL;
    }
    if (argument.owned) {
        lb_hold_temp(lb, argument.v); // a borrowed argument lives to the end of the statement
    }
    const MirValue slot = lbd_slot(lb);
    const MirValue put[2] = {slot, mir_b_use_var(&lb->b, lb->var_of[binding])};
    (void)mir_b_emit(&lb->b, MOP_Put, put, 2, (MirImm){0}, MIR_NONE);
    if (text) {
        (void)lbd_call(lb, "msrt_strbuilder_append", slot, argument.v);
    } else if (bytes) {
        (void)lbd_call(lb, "msrt_bytes_extend", slot, argument.v);
    } else {
        lbd_push_byte(lb, slot, argument.v);
    }
    const MirValue back = mir_b_emit(&lb->b, MOP_Take, &slot, 1, (MirImm){.tag = MI_TY, .a = MIR_BYTES}, MIR_BYTES);
    mir_b_def_var(&lb->b, lb->var_of[binding], back);
    return (LbVal){mir_b_unit(&lb->b), false};
}

/* `builder.build()`: the consumed buffer, frozen into text for a `StringBuilder`. */
static LbVal lbd_build(Lb *lb, const MsExpr *receiver, MirTy result_ty) {
    const MirValue buffer = lb_move_argument(lb, receiver); // a local `var` is copied: its scope still drops it
    if (!lb->ok) {
        return LB_FAIL;
    }
    if (result_ty != MIR_STR) {
        return (LbVal){buffer, true};
    }
    const MirValue slot = lbd_slot(lb);
    const MirValue put[2] = {slot, buffer};
    (void)mir_b_emit(&lb->b, MOP_Put, put, 2, (MirImm){0}, MIR_NONE);
    const MirTy types[1] = {MIR_PTR};
    const uint32_t ext = lb_runtime_extern(lb, "msrt_strbuilder_freeze", types, 1, MIR_STR, MR_NONE, false);
    return (LbVal){mir_b_call_rt(&lb->b, ext, &slot, 1), true};
}

/* A method of a builder, when it is one this file lowers; false leaves the call to the others. */
bool lbd_method(Lb *lb, const MsExpr *e, LbVal *out) {
    const MsExpr *callee = e->u.call.callee;
    const MsTy receiver_ty = lb->facts->call_receiver[e->id];
    if (receiver_ty == MS_TY_NONE || !lbd_is_builder(lb, receiver_ty)) {
        return false;
    }
    const MsNames *names = lb->c->names;
    const MsSym name = callee->u.member.name;
    const bool text = ms_name_is(names, lb->c->tys.name[lb_ty(lb, receiver_ty)], "StringBuilder");
    if (ms_name_is(names, name, "build") && e->u.call.args.len == 0) {
        *out = lbd_build(lb, callee->u.member.left, lb_mir_ty(lb, lb->facts->expr_ty[e->id]));
        return true;
    }
    const bool bytes = !text && ms_name_is(names, name, "append_bytes");
    if ((ms_name_is(names, name, "append") || bytes) && e->u.call.args.len == 1) {
        const uint32_t binding = lb_var_receiver(lb, callee->u.member.left);
        *out = binding == MS_NONE ? LB_UNSUPPORTED(lb) : lbd_append(lb, e, binding, text, bytes);
        return true;
    }
    return false;
}

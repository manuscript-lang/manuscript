/* Conversions between the numbers (`to_int16`, `to_float`, `to_uint8`, ...): operations of a number's own
 * interface that no runtime function implements. Widening is exact, narrowing an integer gives an Optional, and
 * a float conversion rounds to the target (crates/ms-lower native.rs `numeric_conversion`). */
#include <ctype.h>
#include <string.h>

#include "ms/lower_internal.h"

static bool ln_is_int(MirTy ty) {
    return ty == MIR_INT || ty == MIR_INT8 || ty == MIR_INT16 || ty == MIR_INT32 || ty == MIR_UINT8 ||
           ty == MIR_UINT16 || ty == MIR_UINT32 || ty == MIR_UINT64;
}

static bool ln_is_float(MirTy ty) { return ty == MIR_FLOAT || ty == MIR_FLOAT32; }

/* Whether `name` is `to_` and a primitive type's name in lowercase (`to_int16`, `to_float`): how an operation of a
 * number's interface says it converts. */
bool lb_is_conversion_name(const Lb *lb, MsSym name) {
    const MsStr text = ms_name(lb->c->names, name);
    if (text.len < 4 || memcmp(text.ptr, "to_", 3) != 0) {
        return false;
    }
    for (size_t i = 0; i < ms_primitive_count(); i++) {
        const char *primitive = ms_primitive_name(i);
        bool same = strlen(primitive) == text.len - 3;
        for (size_t j = 0; same && j < text.len - 3; j++) {
            same = tolower((unsigned char)primitive[j]) == (unsigned char)text.ptr[3 + j];
        }
        if (same) {
            return true;
        }
    }
    return false;
}

/* The target of a conversion whose result is `some` of an integer: the integer type, or MIR_NONE. */
static MirTy ln_narrowed(Lb *lb, MsTy checked_result) {
    const MsTyTable *tys = &lb->c->tys;
    if (!ms_ty_is(tys, checked_result, MS_BI_OPTIONAL) || tys->nargs[checked_result] != 1) {
        return MIR_NONE;
    }
    const MirTy inner = lb_mir_ty(lb, ms_ty_args(tys, checked_result)[0]);
    return ln_is_int(inner) ? inner : MIR_NONE;
}

/* `x` converted to `checked_result`, when `x` is a number and the result is one (or an Optional integer):
 * `inarrow.opt` for an integer that may not fit, `i2f` from an integer, `conv` between sizes. A `UInt64` has no
 * float conversion here: those are runtime calls. */
bool lb_numeric_conversion(Lb *lb, MirValue x, MsTy checked_result, LbVal *out) {
    const MirTy from = mir_b_ty(&lb->b, x);
    const MirTy narrowed = ln_narrowed(lb, checked_result);
    const MirTy result = lb_mir_ty(lb, checked_result);
    if (!lb->ok || !(ln_is_int(from) || ln_is_float(from))) {
        return false;
    }
    if (narrowed != MIR_NONE && ln_is_int(from)) {
        *out = (LbVal){mir_b_emit(&lb->b, MOP_INarrowOpt, &x, 1, (MirImm){0}, result), false};
        return true;
    }
    if (!ln_is_int(result) && !ln_is_float(result)) {
        return false;
    }
    MirValue converted = x;
    if (ln_is_float(result) && ln_is_int(from)) {
        if (from == MIR_UINT64) {
            return false;
        }
        converted = mir_b_emit(&lb->b, MOP_I2F, &x, 1, (MirImm){0}, result);
    } else if (ln_is_int(result) && ln_is_float(from)) {
        return false; // a float to an integer reports failure: a runtime call
    }
    if (mir_b_ty(&lb->b, converted) != result) {
        converted = mir_b_emit(&lb->b, MOP_Conv, &converted, 1, (MirImm){0}, result);
    }
    *out = (LbVal){converted, false};
    return true;
}

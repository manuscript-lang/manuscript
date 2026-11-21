/* Maps in the lowering: a `Map[K, V]` of an Int or Bool key and an Int, Float or Bool value is the
 * runtime object `Map<K, V>`. A literal builds it with `msrt_map_new` and one `msrt_map_add` per entry
 * (key and value pass in stack slots), `m[k]` asks `msrt_map_get_ptr` for the value and faults when
 * the key is absent. A map is owned like a list: a local made from a literal owns it, a parameter
 * borrows it. Owned keys and values, and the map methods, wait for the ownership side. */
#include <stdio.h>
#include <string.h>

#include "ms/lower_internal.h"
#include "ms/mir_pass.h"

static bool lm_scalar_key(MirTy ty) {
    return ty == MIR_INT || ty == MIR_BOOL;
}

MirTy lm_type(Lb *lb, MsTy ty) {
    const MsTyTable *tys = &lb->c->tys;
    if (!ms_ty_is(tys, ty, MS_BI_MAP) || tys->nargs[ty] != 2) {
        return MIR_NONE;
    }
    const MirTy args[2] = {lb_mir_ty(lb, ms_ty_args(tys, ty)[0]), lb_mir_ty(lb, ms_ty_args(tys, ty)[1])};
    if (!lm_scalar_key(args[0]) || !lb_is_scalar(args[1])) {
        return MIR_NONE;
    }
    return mir_ty_obj(lb->m, mir_name(lb->m, "Map", 3), args, 2);
}

bool lb_is_map(const Lb *lb, MirTy ty) {
    if (ty == MIR_NONE) {
        return false;
    }
    const MirTyData *data = mir_ty_data(lb->m, ty);
    return data->kind == MK_OBJ && data->nargs == 2 && mir_name_is(lb->m, data->name, "Map");
}

/* The runtime function `name`, declared on first use with its borrowed parameters. */
static uint32_t lm_extern(Lb *lb, const char *name, const MirTy *params, uint32_t nparams, MirTy ret, uint8_t role) {
    return mir_extern_get(lb->m, name, params, nparams, ret, true, (MirRole)role);
}

static MirImm lm_str(Lb *lb, const char *text, size_t length) {
    return (MirImm){.tag = MI_STR, .a = mir_add_string(lb->m, text, length)};
}

static MirValue lm_slot(Lb *lb, MirTy ty) {
    return mir_b_emit(&lb->b, MOP_Slot, NULL, 0, (MirImm){.tag = MI_TY, .a = ty}, MIR_PTR);
}

static MirValue lm_desc(Lb *lb, MirTy ty) {
    return mir_b_emit(&lb->b, MOP_TypeDesc, NULL, 0, (MirImm){.tag = MI_TY, .a = ty}, MIR_PTR);
}

/* `{k: v, ...}`: the map lives in one slot while the entries are added, then is taken back. */
LbVal lm_literal(Lb *lb, const MsExpr *e) {
    const MirTy ty = lb_mir_ty(lb, lb->facts->expr_ty[e->id]);
    if (!lb_is_map(lb, ty)) {
        return lb_unsupported(lb);
    }
    const MirTyData *data = mir_ty_data(lb->m, ty);
    const MirTy key_ty = data->args[0];
    const MirTy value_ty = data->args[1];
    const uint32_t make = lm_extern(lb, "msrt_map_new", NULL, 0, ty, MR_MAP_NEW);
    const MirValue empty = mir_b_call_rt(&lb->b, make, NULL, 0);
    const MirValue key_desc = lm_desc(lb, key_ty);
    const MirValue value_desc = lm_desc(lb, value_ty);
    const MirValue map_slot = lm_slot(lb, ty);
    const MirValue put[2] = {map_slot, empty};
    (void)mir_b_emit(&lb->b, MOP_Put, put, 2, (MirImm){0}, MIR_NONE);
    const MirTy ptr5[5] = {MIR_PTR, MIR_PTR, MIR_PTR, MIR_PTR, MIR_PTR};
    const uint32_t add = lm_extern(lb, "msrt_map_add", ptr5, 5, MIR_VOID, MR_NONE);
    MirValue key_slot = MIR_NONE;
    MirValue value_slot = MIR_NONE;
    for (uint32_t i = 0; i < e->u.map.len && lb->ok; i++) {
        const MirValue key = lb_expr(lb, e->u.map.ptr[i].key).v;
        const MirValue value = lb_expr(lb, e->u.map.ptr[i].value).v;
        if (!lb->ok) {
            return LB_FAIL;
        }
        if (key_slot == MIR_NONE) { // one pair of slots serves every entry
            key_slot = lm_slot(lb, key_ty);
            value_slot = lm_slot(lb, value_ty);
        }
        lb_store(lb, key_slot, key);
        lb_store(lb, value_slot, value);
        const MirValue args[5] = {map_slot, key_desc, value_desc, key_slot, value_slot};
        (void)mir_b_call_rt(&lb->b, add, args, 5);
    }
    if (!lb->ok) {
        return LB_FAIL;
    }
    return (LbVal){mir_b_emit(&lb->b, MOP_Take, &map_slot, 1, (MirImm){.tag = MI_TY, .a = ty}, ty), true};
}

/* The message of a missing key: `map key not found: 7` for an Int key, the bare head for a Bool. */
static MirValue lm_missing_message(Lb *lb, MirValue key) {
    static const char head[] = "map key not found";
    if (mir_b_ty(&lb->b, key) != MIR_INT) {
        return mir_b_emit(&lb->b, MOP_StrLit, NULL, 0, lm_str(lb, head, sizeof head - 1), MIR_STR);
    }
    const MirTy int_param[1] = {MIR_INT};
    const MirTy str_params[2] = {MIR_STR, MIR_STR};
    const MirValue label = mir_b_emit(&lb->b, MOP_StrLit, NULL, 0, lm_str(lb, "map key not found: ", 19), MIR_STR);
    const MirValue digits = mir_b_call_rt(&lb->b, lm_extern(lb, "msrt_int_to_string", int_param, 1, MIR_STR, MR_INT_TO_STRING), &key, 1);
    const MirValue pair[2] = {label, digits};
    return mir_b_call_rt(&lb->b, lm_extern(lb, "msrt_string_concat", str_params, 2, MIR_STR, MR_STRING_CONCAT), pair, 2);
}

/* `map[key]` with the lowered receiver `map`: the map is borrowed for the lookup and dropped after
 * it when it is a temporary. */
LbVal lm_index(Lb *lb, LbVal map, const MsExpr *at) {
    const MirTy ty = mir_b_ty(&lb->b, map.v);
    const MirTyData *data = mir_ty_data(lb->m, ty);
    const LbVal key = lb_expr(lb, at);
    if (!lb->ok || mir_b_ty(&lb->b, key.v) != data->args[0]) {
        return lb_unsupported(lb);
    }
    const MirValue map_slot = lm_slot(lb, ty);
    lb_store(lb, map_slot, map.v);
    const MirValue key_slot = lm_slot(lb, data->args[0]);
    lb_store(lb, key_slot, key.v);
    const MirTy ptr4[4] = {MIR_PTR, MIR_PTR, MIR_PTR, MIR_PTR};
    const MirValue lookup[4] = {map_slot, lm_desc(lb, data->args[0]), lm_desc(lb, data->args[1]), key_slot};
    const MirValue found = mir_b_call_rt(&lb->b, lm_extern(lb, "msrt_map_get_ptr", ptr4, 4, MIR_PTR, MR_NONE), lookup, 4);
    const MirValue absent = mir_b_emit(&lb->b, MOP_PtrIsNull, &found, 1, (MirImm){0}, MIR_BOOL);
    const MirBlock missing = mir_b_new_block(&lb->b);
    const MirBlock present = mir_b_new_block(&lb->b);
    mir_b_br_if(&lb->b, absent, missing, NULL, 0, present, NULL, 0);
    mir_b_seal_block(&lb->b, missing);
    mir_b_seal_block(&lb->b, present);
    lb_enter(lb, missing);
    const MirTy fault_param[1] = {MIR_STR};
    const uint32_t fault = mir_extern_get(lb->m, "msrt_fault_string", fault_param, 1, MIR_VOID, true, MR_NONE);
    lb->m->externs[fault].noreturn = true;
    const MirValue message = lm_missing_message(lb, key.v);
    (void)mir_b_call_rt(&lb->b, fault, &message, 1);
    mir_b_unreachable(&lb->b);
    lb_enter(lb, present);
    const MirValue value = mir_b_emit(&lb->b, MOP_Load, &found, 1, (MirImm){.tag = MI_TY, .a = data->args[1]}, data->args[1]);
    if (map.owned) {
        lb_drop(lb, map.v);
    }
    return (LbVal){value, false};
}

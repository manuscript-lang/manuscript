/* Maps in the lowering: a `Map[K, V]` is the runtime object `Map<K, V>` over any key and value type the
 * lowering has a MIR type for; layout, hash, equality and drop come from the type descriptors. A literal builds it with `msrt_map_new` and one `msrt_map_add` per entry
 * (key and value pass in stack slots), `m[k]` asks `msrt_map_get_ptr` for the value and faults when
 * the key is absent. A map is owned like a list: a local made from a literal owns it, a parameter
 * borrows it. Owned keys and values, and the map methods, wait for the ownership side. */
#include <stdio.h>
#include <string.h>

#include "ms/lower_internal.h"
#include "ms/mir_layout.h"
#include "ms/mir_pass.h"
#include "ms/rt_ops.h"

MirTy lm_type(Lb *lb, MsTy ty) {
    const MsTyTable *tys = &lb->c->tys;
    if (!ms_ty_is(tys, ty, MS_BI_MAP) || tys->nargs[ty] != 2) {
        return MIR_NONE;
    }
    const MirTy args[2] = {lb_mir_ty(lb, ms_ty_args(tys, ty)[0]), lb_mir_ty(lb, ms_ty_args(tys, ty)[1])};
    if (args[0] == MIR_NONE || args[1] == MIR_NONE) { // layout, hash, equality and drop come from the type descriptors
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

/* The runtime function `name` over these borrowed parameters, declared on first use: the same name
 * over other types is another declaration (`msrt_map_new` returns each map type). */
uint32_t lb_runtime_extern(Lb *lb, const char *name, const MirTy *params, uint32_t nparams, MirTy ret, uint8_t role,
                          bool reads) {
    const MsSym sym = mir_name(lb->m, name, strlen(name));
    MirParam *wanted = MS_NEW_N(&lb->m->arena, MirParam, nparams + 1);
    for (uint32_t i = 0; i < nparams; i++) {
        wanted[i] = (MirParam){params[i], MM_BORROW};
    }
    for (uint32_t i = 0; i < lb->m->nexterns; i++) {
        const MirExtern *known = &lb->m->externs[i];
        if (known->name == sym && known->nparams == nparams && known->ret == ret &&
            (nparams == 0 || memcmp(known->params, wanted, (size_t)nparams * sizeof *wanted) == 0)) {
            return i;
        }
    }
    const MirExtern ext = {.name = sym, .params = wanted, .nparams = nparams, .ret = ret, .leaf = true,
                           .reads = reads, .role = role};
    return mir_add_extern(lb->m, &ext);
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

/* Fills `slot` with a key or value the map takes: an owned one is put (the slot now owns it), a plain
 * one is stored. */
static void lm_fill(Lb *lb, MirValue slot, MirValue value) {
    const MirValue args[2] = {slot, value};
    (void)mir_b_emit(&lb->b, lb_owns(lb, mir_b_ty(&lb->b, value)) ? MOP_Put : MOP_Store, args, 2, (MirImm){0}, MIR_NONE);
}

/* A key or value the map takes: an owned type moves in, anything else is read. */
static MirValue lm_entry(Lb *lb, const MsExpr *e, MirTy ty) {
    return lb_owns(lb, ty) ? lb_move_argument(lb, e) : lb_expr(lb, e).v;
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
    const uint32_t make = lb_runtime_extern(lb, "msrt_map_new", NULL, 0, ty, MR_MAP_NEW, false);
    const MirValue empty = mir_b_call_rt(&lb->b, make, NULL, 0);
    const MirTy ptr5[5] = {MIR_PTR, MIR_PTR, MIR_PTR, MIR_PTR, MIR_PTR};
    const uint32_t add = lb_runtime_extern(lb, "msrt_map_add", ptr5, 5, MIR_VOID, MR_NONE, false);
    const bool single = e->u.map.len == 1; // one entry is read before the map is put in its slot, and gets slots of its own
    MirValue first_key = MIR_NONE;
    MirValue first_value = MIR_NONE;
    if (single) {
        first_key = lm_entry(lb, e->u.map.ptr[0].key, key_ty);
        first_value = lm_entry(lb, e->u.map.ptr[0].value, value_ty);
        if (!lb->ok) {
            return LB_FAIL;
        }
    }
    const MirValue key_desc = single ? MIR_NONE : lm_desc(lb, key_ty);
    const MirValue value_desc = single ? MIR_NONE : lm_desc(lb, value_ty);
    const MirValue map_slot = lm_slot(lb, ty);
    const MirValue put[2] = {map_slot, empty};
    (void)mir_b_emit(&lb->b, MOP_Put, put, 2, (MirImm){0}, MIR_NONE);
    if (single) {
        const MirValue descs[2] = {lm_desc(lb, key_ty), lm_desc(lb, value_ty)};
        const MirValue key_slot = lm_slot(lb, key_ty);
        lm_fill(lb, key_slot, first_key);
        const MirValue value_slot = lm_slot(lb, value_ty);
        lm_fill(lb, value_slot, first_value);
        const MirValue args[5] = {map_slot, descs[0], descs[1], key_slot, value_slot};
        (void)mir_b_call_rt(&lb->b, add, args, 5);
        return (LbVal){mir_b_emit(&lb->b, MOP_Take, &map_slot, 1, (MirImm){.tag = MI_TY, .a = ty}, ty), true};
    }
    MirValue key_slot = MIR_NONE;
    MirValue value_slot = MIR_NONE;
    for (uint32_t i = 0; i < e->u.map.len && lb->ok; i++) {
        const MirValue key = lm_entry(lb, e->u.map.ptr[i].key, key_ty);
        const MirValue value = lm_entry(lb, e->u.map.ptr[i].value, value_ty);
        if (!lb->ok) {
            return LB_FAIL;
        }
        if (key_slot == MIR_NONE) { // one pair of slots serves every entry
            key_slot = lm_slot(lb, key_ty);
            value_slot = lm_slot(lb, value_ty);
        }
        lm_fill(lb, key_slot, key);
        lm_fill(lb, value_slot, value);
        const MirValue args[5] = {map_slot, key_desc, value_desc, key_slot, value_slot};
        (void)mir_b_call_rt(&lb->b, add, args, 5);
    }
    if (!lb->ok) {
        return LB_FAIL;
    }
    return (LbVal){mir_b_emit(&lb->b, MOP_Take, &map_slot, 1, (MirImm){.tag = MI_TY, .a = ty}, ty), true};
}

/* The message of a missing key: `map key not found: 7` for an Int key, `map key not found: "k"` for a
 * String, the bare head for a Bool. */
static MirValue lm_missing_message(Lb *lb, MirValue key) {
    static const char head[] = "map key not found";
    const MirTy key_ty = mir_b_ty(&lb->b, key);
    const MirTy int_param[1] = {MIR_INT};
    if (key_ty == MIR_STR) {
        const MirValue open = mir_b_emit(&lb->b, MOP_StrLit, NULL, 0, lm_str(lb, "map key not found: \"", 20), MIR_STR);
        const MirValue close = mir_b_emit(&lb->b, MOP_StrLit, NULL, 0, lm_str(lb, "\"", 1), MIR_STR);
        const uint32_t join = lb_string_concat(lb);
        const MirValue first[2] = {open, key};
        const MirValue text = mir_b_call_rt(&lb->b, join, first, 2);
        const MirValue last[2] = {text, close};
        return mir_b_call_rt(&lb->b, join, last, 2);
    }
    if (key_ty != MIR_INT) {
        return mir_b_emit(&lb->b, MOP_StrLit, NULL, 0, lm_str(lb, head, sizeof head - 1), MIR_STR);
    }
    const MirValue label = mir_b_emit(&lb->b, MOP_StrLit, NULL, 0, lm_str(lb, "map key not found: ", 19), MIR_STR);
    const MirValue digits = mir_b_call_rt(&lb->b, lb_runtime_extern(lb, "msrt_int_to_string", int_param, 1, MIR_STR, MR_INT_TO_STRING, false), &key, 1);
    const MirValue pair[2] = {label, digits};
    return mir_b_call_rt(&lb->b, lb_string_concat(lb), pair, 2);
}

typedef enum LmShape { LM_GENERAL, LM_WORD, LM_TEXT } LmShape;

/* The key and value layout of a map, read from the layout leaves: a key of one integer word or a String,
 * over a value of one word, has a fixed slot layout the runtime probes without descriptor dispatch. */
static LmShape lm_shape(Lb *lb, MirTy key, MirTy value) {
    MirLayouts layouts;
    mir_layouts_init(&layouts, lb->m);
    const MirLeafSpan key_leaves = mir_leaves(&layouts, key);
    const MirLeafSpan value_leaves = mir_leaves(&layouts, value);
    const bool word_value = value_leaves.len == 1 && !mir_pointer_leaves(&layouts, value)[0] &&
                            (value_leaves.ptr[0] == MIR_LEAF_I64 || value_leaves.ptr[0] == MIR_LEAF_F64);
    const bool word_key = key_leaves.len == 1 && key_leaves.ptr[0] == MIR_LEAF_I64 && !mir_pointer_leaves(&layouts, key)[0];
    const bool text_key = mir_ty_data(lb->m, key)->kind == MK_STR;
    mir_layouts_free(&layouts);
    if (!word_value) {
        return LM_GENERAL;
    }
    return word_key ? LM_WORD : (text_key ? LM_TEXT : LM_GENERAL);
}

/* The entry of `generic` that fits a map of `key` and `value`: the specialisation the runtime declares
 * for the layout (`@word_key_of`, `@text_key_of`), else `generic` itself. */
const MsRtFn *lm_specialize(Lb *lb, const MsRtFn *generic, MirTy key, MirTy value) {
    const LmShape shape = lm_shape(lb, key, value);
    const char *twin = shape == LM_WORD ? generic->word_twin : (shape == LM_TEXT ? generic->text_twin : "");
    const MsRtFn *found = twin[0] != '\0' ? ms_rt_fn_find(twin, strlen(twin)) : NULL;
    return found != NULL ? found : generic;
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
    const MirValue key_desc = lm_desc(lb, data->args[0]);
    const MirValue value_desc = lm_desc(lb, data->args[1]);
    const MirValue key_slot = lm_slot(lb, data->args[0]);
    lb_store(lb, key_slot, key.v);
    const MsRtFn *entry = lm_specialize(lb, ms_rt_fn_find("msrt_map_get_ptr", strlen("msrt_map_get_ptr")), data->args[0], data->args[1]);
    const MirTy params[4] = {ty, MIR_PTR, MIR_PTR, MIR_PTR};
    const uint32_t lookup_fn = lb_runtime_extern(lb, entry->symbol, params, 4, MIR_PTR, MR_NONE, entry->pure);
    const MirValue lookup[4] = {map.v, key_desc, value_desc, key_slot};
    const MirValue found = mir_b_call_rt(&lb->b, lookup_fn, lookup, 4);
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
    if (key.owned) {
        lb_drop(lb, key.v);
    }
    if (map.owned) {
        lb_drop(lb, map.v);
    }
    return (LbVal){value, false};
}

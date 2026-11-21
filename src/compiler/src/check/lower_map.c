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
    if (ms_ty_is(tys, ty, MS_BI_SET) && tys->nargs[ty] == 1) {
        const MirTy element = lb_mir_ty(lb, ms_ty_args(tys, ty)[0]);
        return element == MIR_NONE ? MIR_NONE : mir_ty_obj(lb->m, mir_name(lb->m, "Set", 3), &element, 1);
    }
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

bool lb_is_set(const Lb *lb, MirTy ty) {
    if (ty == MIR_NONE) {
        return false;
    }
    const MirTyData *data = mir_ty_data(lb->m, ty);
    return data->kind == MK_OBJ && data->nargs == 1 && mir_name_is(lb->m, data->name, "Set");
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

/* Fills `dest` with a key or value the map takes: an owned one is put (the slot now owns it), a plain
 * one is stored. */
static void lm_fill(Lb *lb, MirValue dest, MirValue item) {
    const MirValue args[2] = {dest, item};
    (void)mir_b_emit(&lb->b, lb_owns(lb, mir_b_ty(&lb->b, item)) ? MOP_Put : MOP_Store, args, 2, (MirImm){0}, MIR_NONE);
}

/* A key or value the map takes: an owned type moves in, anything else is read. */
static MirValue lm_entry(Lb *lb, const MsExpr *e, MirTy ty) {
    return lb_owns(lb, ty) ? lb_move_argument(lb, e) : lb_expr(lb, e).v;
}

/* `Map[K, V]()`: an empty map. */
LbVal lm_empty(Lb *lb, MirTy ty) {
    if (!lb_is_map(lb, ty) && !lb_is_set(lb, ty)) {
        return LB_UNSUPPORTED(lb);
    }
    const uint32_t make = lb_runtime_extern(lb, "msrt_map_new", NULL, 0, ty, MR_MAP_NEW, false);
    return (LbVal){mir_b_call_rt(&lb->b, make, NULL, 0), true};
}

/* `{k: v, ...}`: the map lives in one slot while the entries are added, then is taken back. */
LbVal lm_literal(Lb *lb, const MsExpr *e) {
    const MirTy ty = lb_mir_ty(lb, lb->facts->expr_ty[e->id]);
    if (!lb_is_map(lb, ty)) {
        return LB_UNSUPPORTED(lb);
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
    if (word_key) {
        return LM_WORD;
    }
    return text_key ? LM_TEXT : LM_GENERAL;
}

/* The entry of `generic` that fits a map of `key` and `value`: the specialisation the runtime declares
 * for the layout (`@word_key_of`, `@text_key_of`), else `generic` itself. `role` is the probe role of
 * the layout, which the optimiser reads to inline the lookup, or MR_NONE. */
const MsRtFn *lm_specialize(Lb *lb, const MsRtFn *generic, MirTy key, MirTy value, uint8_t *role) {
    const LmShape shape = lm_shape(lb, key, value);
    const char *twin = "";
    uint8_t probe = MR_NONE;
    if (shape == LM_WORD) {
        twin = generic->word_twin;
        probe = MR_MAP_PROBE_INT;
    } else if (shape == LM_TEXT) {
        twin = generic->text_twin;
        probe = MR_MAP_PROBE_STR;
    }
    const MsRtFn *found = twin[0] != '\0' ? ms_rt_fn_find(twin, strlen(twin)) : NULL;
    *role = found != NULL ? probe : MR_NONE;
    return found != NULL ? found : generic;
}

/* `map[key]` with the lowered receiver `map`: the map is borrowed for the lookup and dropped after
 * it when it is a temporary. */
LbVal lm_index(Lb *lb, LbVal map, const MsExpr *at) {
    const MirTy ty = mir_b_ty(&lb->b, map.v);
    const MirTyData *data = mir_ty_data(lb->m, ty);
    const LbVal key = lb_expr(lb, at);
    if (!lb->ok || mir_b_ty(&lb->b, key.v) != data->args[0]) {
        return LB_UNSUPPORTED(lb);
    }
    const MirValue key_desc = lm_desc(lb, data->args[0]);
    const MirValue value_desc = lm_desc(lb, data->args[1]);
    const MirValue key_slot = lm_slot(lb, data->args[0]);
    lb_store(lb, key_slot, key.v);
    uint8_t role = MR_NONE;
    const MsRtFn *entry = lm_specialize(lb, ms_rt_fn_find("msrt_map_get_ptr", strlen("msrt_map_get_ptr")), data->args[0], data->args[1], &role);
    const MirTy params[4] = {ty, MIR_PTR, MIR_PTR, MIR_PTR};
    const uint32_t lookup_fn = lb_runtime_extern(lb, entry->symbol, params, 4, MIR_PTR, role, entry->pure);
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

/* A key or value argument of a mutator, evaluated: filled into its slot by `lm_fill_arg`. */
static LbVal lm_arg(Lb *lb, const MsExpr *e) {
    return lb_expr(lb, e);
}

/* Puts the argument `item` into a fresh slot of `ty`: an owned type is moved in (a borrowed one is copied first), a
 * plain one is stored. */
static MirValue lm_take_arg(Lb *lb, LbVal item, MirTy ty) {
    const MirValue slot = lm_slot(lb, ty);
    if (lb_owns(lb, ty)) {
        lm_fill(lb, slot, item.owned ? item.v : lb_copy(lb, item.v));
    } else {
        lm_fill(lb, slot, item.v);
    }
    return slot;
}

/* A key only read by the runtime (`remove`): stored in a slot, and a temporary is dropped with the statement. */
static MirValue lm_read_arg(Lb *lb, LbVal item, MirTy ty) {
    const MirValue slot = lm_slot(lb, ty);
    const MirValue args[2] = {slot, item.v};
    (void)mir_b_emit(&lb->b, MOP_Store, args, 2, (MirImm){0}, MIR_NONE);
    if (item.owned) {
        lb_hold_temp(lb, item.v);
    }
    return slot;
}

/* A mutator of the `var` map or set `binding`: the container goes through a slot and comes back to the local. */
static LbVal lm_mutate(Lb *lb, const MsExpr *e, uint32_t binding, bool set, bool add, bool remove) {
    const MirTy ty = mir_b_ty(&lb->b, mir_b_use_var(&lb->b, lb->var_of[binding]));
    const MirTyData *data = mir_ty_data(lb->m, ty);
    const MirTy key_ty = data->args[0];
    const MirTy value_ty = set ? MIR_INT : data->args[1]; // a set has no values: the runtime is passed a plain word
    LbVal key = LB_FAIL;
    LbVal value = LB_FAIL;
    if (add || remove) {
        key = lm_arg(lb, e->u.call.args.ptr[0].value);
    }
    if (add && !set) {
        value = lm_arg(lb, e->u.call.args.ptr[1].value);
    }
    if (!lb->ok) {
        return LB_FAIL;
    }
    const MirValue slot = lm_slot(lb, ty);
    const MirValue put[2] = {slot, mir_b_use_var(&lb->b, lb->var_of[binding])};
    (void)mir_b_emit(&lb->b, MOP_Put, put, 2, (MirImm){0}, MIR_NONE);
    const MirValue key_desc = lm_desc(lb, key_ty);
    const MirValue value_desc = set ? MIR_NONE : lm_desc(lb, value_ty);
    const MirValue placeholder = set && !add ? mir_b_iconst(&lb->b, 0) : MIR_NONE;
    const LmShape shape = lm_shape(lb, key_ty, set ? MIR_INT : value_ty);
    MirValue args[5] = {slot, key_desc, set ? placeholder : value_desc, MIR_NONE, MIR_NONE};
    uint32_t count = 3;
    const char *name = "msrt_map_clear";
    if (add && set) {
        name = key_ty == MIR_INT ? "msrt_set_add_copy_w" : "msrt_set_add_copy"; // only `Set[Int]` has the fixed slot layout
        args[2] = lm_read_arg(lb, key, key_ty); // the runtime copies the value in (`add_copy`)
    } else if (add) {
        name = shape == LM_WORD && key_ty == MIR_INT ? "msrt_map_add_w8" : shape == LM_TEXT ? "msrt_map_add_sw8" : "msrt_map_add";
        args[3] = lm_take_arg(lb, key, key_ty);
        args[4] = lm_take_arg(lb, value, value_ty);
        count = 5;
    } else if (remove) {
        name = "msrt_map_remove";
        args[3] = lm_read_arg(lb, key, key_ty);
        count = 4;
    }
    MirTy types[5];
    for (uint32_t i = 0; i < count; i++) {
        types[i] = mir_b_ty(&lb->b, args[i]);
    }
    (void)mir_b_call_rt(&lb->b, lb_runtime_extern(lb, name, types, count, MIR_VOID, MR_NONE, false), args, count);
    const MirValue back = mir_b_emit(&lb->b, MOP_Take, &slot, 1, (MirImm){.tag = MI_TY, .a = ty}, ty);
    mir_b_def_var(&lb->b, lb->var_of[binding], back);
    return (LbVal){mir_b_unit(&lb->b), false};
}

/* `add`, `remove` and `clear` on a `var` Map or Set local; false leaves the call to the others. */
bool lm_mutator(Lb *lb, const MsExpr *e, LbVal *out) {
    const MsExpr *callee = e->u.call.callee;
    const MsTy receiver_ty = lb->facts->call_receiver[e->id];
    if (receiver_ty == MS_TY_NONE) {
        return false;
    }
    const MirTy ty = lb_mir_ty(lb, receiver_ty);
    const bool set = lb_is_set(lb, ty);
    if (!set && !lb_is_map(lb, ty)) {
        return false;
    }
    const MsNames *names = lb->c->names;
    const MsSym name = callee->u.member.name;
    const uint32_t nargs = e->u.call.args.len;
    const bool add = ms_name_is(names, name, "add") && nargs == (set ? 1u : 2u);
    const bool remove = ms_name_is(names, name, "remove") && nargs == 1;
    const bool clear = ms_name_is(names, name, "clear") && nargs == 0;
    if (!add && !remove && !clear) {
        return false;
    }
    const uint32_t binding = lb_var_receiver(lb, callee->u.member.left);
    *out = binding == MS_NONE ? LB_UNSUPPORTED(lb) : lm_mutate(lb, e, binding, set, add, remove);
    return true;
}

/* `length`, `is_empty` and `contains` of a Set: the runtime counts the slots, or probes for the key. */
static LbVal lm_set_query(Lb *lb, const MsExpr *e, bool contains, bool empty) {
    const MsExpr *callee = e->u.call.callee;
    const LbVal set = lb_expr(lb, callee->u.member.left);
    LbVal key = LB_FAIL;
    if (lb->ok && contains) {
        key = lb_expr(lb, e->u.call.args.ptr[0].value);
    }
    if (!lb->ok) {
        return LB_FAIL;
    }
    const MirTy ty = mir_b_ty(&lb->b, set.v);
    MirValue result = MIR_NONE;
    if (contains) {
        const MirTy key_ty = mir_ty_data(lb->m, ty)->args[0];
        const MirValue key_desc = lm_desc(lb, key_ty);
        const MirValue placeholder = mir_b_iconst(&lb->b, 0);
        const MirValue slot = lm_slot(lb, key_ty);
        const MirValue stored[2] = {slot, key.v};
        (void)mir_b_emit(&lb->b, MOP_Store, stored, 2, (MirImm){0}, MIR_NONE);
        const MirValue args[4] = {set.v, key_desc, placeholder, slot};
        const MirTy types[4] = {ty, MIR_PTR, MIR_INT, MIR_PTR};
        const char *name = key_ty == MIR_INT ? "msrt_set_contains_w" : "msrt_map_contains";
        result = mir_b_call_rt(&lb->b, lb_runtime_extern(lb, name, types, 4, MIR_BOOL, MR_NONE, true), args, 4);
    } else {
        const uint32_t length = lb_runtime_extern(lb, "msrt_map_length", &ty, 1, MIR_INT, MR_NONE, true);
        result = mir_b_call_rt(&lb->b, length, &set.v, 1);
        if (empty) {
            result = mir_b_icmp(&lb->b, MCC_EQ, result, mir_b_iconst(&lb->b, 0));
        }
    }
    if (key.owned) {
        lb_hold_temp(lb, key.v);
    }
    if (set.owned) {
        lb_hold_temp(lb, set.v);
    }
    return (LbVal){result, false};
}

/* The queries of a Set no runtime function of its own implements; false leaves the call to the others. */
bool lm_set_method(Lb *lb, const MsExpr *e, LbVal *out) {
    const MsExpr *callee = e->u.call.callee;
    const MsTy receiver_ty = lb->facts->call_receiver[e->id];
    if (receiver_ty == MS_TY_NONE || !lb_is_set(lb, lb_mir_ty(lb, receiver_ty))) {
        return false;
    }
    const MsNames *names = lb->c->names;
    const MsSym name = callee->u.member.name;
    const uint32_t nargs = e->u.call.args.len;
    const bool contains = ms_name_is(names, name, "contains") && nargs == 1;
    const bool length = ms_name_is(names, name, "length") && nargs == 0;
    const bool empty = ms_name_is(names, name, "is_empty") && nargs == 0;
    if (!contains && !length && !empty) {
        return false;
    }
    *out = lm_set_query(lb, e, contains, empty);
    return true;
}

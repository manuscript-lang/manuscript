/* MIR layout: boxing of recursive alternatives and optionals (ir/module.rs `Boxing`). Owns the
 * memo tables of a MirBoxing; the module it reads belongs to the caller. */
#include <stdlib.h>
#include <string.h>

#include "ms/mir_layout.h"
#include "ms/mir_analysis.h"

/* The types visited by one search, so a type reachable twice is walked once. */
typedef struct BoxSeen {
    MirTy *types; /* owned by the boxing arena */
    uint32_t count, capacity;
} BoxSeen;

void mir_boxing_init(MirBoxing *boxing, const MirModule *module) {
    memset(boxing, 0, sizeof *boxing);
    boxing->module = module;
    boxing->alts = MS_NEW_N(&boxing->arena, uint8_t, module->nalts + 1);
    boxing->opts = MS_NEW_N(&boxing->arena, uint8_t, module->types.len + 1);
    memset(boxing->alts, 0, (size_t)module->nalts + 1);
    memset(boxing->opts, 0, (size_t)module->types.len + 1);
}

void mir_boxing_free(MirBoxing *boxing) {
    ms_arena_free(&boxing->arena);
    memset(boxing, 0, sizeof *boxing);
}

static bool seen_has(const BoxSeen *seen, MirTy type) {
    for (uint32_t i = 0; i < seen->count; i++) {
        if (seen->types[i] == type) {
            return true;
        }
    }
    return false;
}

static void seen_add(MirBoxing *boxing, BoxSeen *seen, MirTy type) {
    if (seen->count == seen->capacity) {
        uint32_t capacity = seen->capacity == 0 ? 8 : seen->capacity * 2;
        MirTy *grown = MS_NEW_N(&boxing->arena, MirTy, capacity);
        if (seen->count > 0) {
            memcpy(grown, seen->types, sizeof(MirTy) * seen->count);
        }
        seen->types = grown;
        seen->capacity = capacity;
    }
    seen->types[seen->count++] = type;
}

static bool reaches_by_value(MirBoxing *boxing, MirTy from, MirTy target, BoxSeen *seen);

/* One field type of the type being searched: true when it is the target or leads to it by value. */
static bool reaches_through(MirBoxing *boxing, MirTy child, MirTy target, BoxSeen *seen) {
    if (child == target) {
        return true;
    }
    if (seen_has(seen, child)) {
        return false;
    }
    seen_add(boxing, seen, child);
    const MirTyData *data = mir_ty_data(boxing->module, child);
    /* Another boxed alternative or optional is one pointer: the search stops there. */
    if (data->kind == MK_ALT && mir_boxing_alt(boxing, data->id)) {
        return false;
    }
    if (data->kind == MK_OPT && mir_boxing_opt(boxing, data->elem)) {
        return false;
    }
    return reaches_by_value(boxing, child, target, seen);
}

static bool reaches_in_fields(MirBoxing *boxing, const MirField *fields, uint32_t count,
                              MirTy target, BoxSeen *seen) {
    for (uint32_t i = 0; i < count; i++) {
        if (reaches_through(boxing, fields[i].ty, target, seen)) {
            return true;
        }
    }
    return false;
}

static bool reaches_by_value_inner(MirBoxing *boxing, const MirTyData *data, MirTy target,
                                   BoxSeen *seen) {
    const MirModule *module = boxing->module;
    switch ((MirTyKind)data->kind) {
    case MK_TYPE: {
        const MirTypeDef *def = &module->type_defs[data->id];
        return reaches_in_fields(boxing, def->fields, def->nfields, target, seen);
    }
    case MK_ALT: {
        const MirAltDef *def = &module->alts[data->id];
        for (uint32_t c = 0; c < def->ncases; c++) {
            const MirCaseDef *which = &def->cases[c];
            if (reaches_in_fields(boxing, which->fields, which->nfields, target, seen)) {
                return true;
            }
        }
        return false;
    }
    case MK_OPT:
        return reaches_through(boxing, data->elem, target, seen);
    case MK_VOID: case MK_BOOL: case MK_INT: case MK_FLOAT: case MK_INT8: case MK_INT16:
    case MK_INT32: case MK_FLOAT32: case MK_UINT8: case MK_UINT16: case MK_UINT32:
    case MK_UINT64: case MK_STR: case MK_BYTES: case MK_PTR: case MK_LIST: case MK_OBJ:
    case MK_FN: case MK_IFACE:
        return false;
    }
    return false;
}

static bool reaches_by_value(MirBoxing *boxing, MirTy from, MirTy target, BoxSeen *seen) {
    if (boxing->depth >= MIR_LAYOUT_MAX_DEPTH) {
        boxing->failed = true;
        return false;
    }
    boxing->depth++;
    bool found = reaches_by_value_inner(boxing, mir_ty_data(boxing->module, from), target, seen);
    boxing->depth--;
    return found;
}

/* Whether the type `target` contains itself by value, starting a fresh visit list. */
static bool contains_itself(MirBoxing *boxing, MirTy target) {
    BoxSeen seen = {0};
    return reaches_by_value(boxing, target, target, &seen);
}

bool mir_boxing_alt(MirBoxing *boxing, uint32_t alt) {
    if (alt >= boxing->module->nalts) {
        return false;
    }
    if (boxing->alts[alt] != 0) {
        return boxing->alts[alt] == 2;
    }
    /* Provisional answer for cycles through other alternatives. */
    boxing->alts[alt] = 1;
    const MirTyData key = {.kind = MK_ALT, .id = alt};
    MirTy type = 0;
    bool boxed = mir_ty_find(boxing->module, &key, &type) && contains_itself(boxing, type);
    boxing->alts[alt] = boxed ? 2 : 1;
    return boxed;
}

bool mir_boxing_opt(MirBoxing *boxing, MirTy inner) {
    if (inner >= boxing->module->types.len) {
        return false;
    }
    if (boxing->opts[inner] != 0) {
        return boxing->opts[inner] == 2;
    }
    boxing->opts[inner] = 1;
    const MirTyData key = {.kind = MK_OPT, .elem = inner};
    MirTy type = 0;
    bool boxed = mir_ty_find(boxing->module, &key, &type) && contains_itself(boxing, type);
    boxing->opts[inner] = boxed ? 2 : 1;
    return boxed;
}

bool mir_alt_is_boxed(const MirModule *module, uint32_t alt) {
    MirBoxing boxing;
    mir_boxing_init(&boxing, module);
    bool boxed = mir_boxing_alt(&boxing, alt);
    mir_boxing_free(&boxing);
    return boxed;
}

bool mir_opt_is_boxed(const MirModule *module, MirTy inner) {
    MirBoxing boxing;
    mir_boxing_init(&boxing, module);
    bool boxed = mir_boxing_opt(&boxing, inner);
    mir_boxing_free(&boxing);
    return boxed;
}

/* Whether the runtime takes a value of `ty` as its scalar leaves: scalars, pointers, handles and
 * the small optionals of them. Anything else crosses as the address of a copy. */
bool mir_rt_direct(const MirModule *m, MirLayouts *layouts, MirTy ty) {
    const MirTyData *data = mir_ty_data(m, ty);
    switch ((MirTyKind)data->kind) {
    case MK_VOID: case MK_BOOL: case MK_INT: case MK_INT8: case MK_INT16: case MK_INT32:
    case MK_UINT8: case MK_UINT16: case MK_UINT32: case MK_UINT64: case MK_FLOAT:
    case MK_FLOAT32: case MK_PTR: case MK_FN: case MK_IFACE:
        return true;
    case MK_OBJ:
        return data->obj_class != MIR_OBJ_COLLECTION;
    case MK_OPT:
        return mir_opt_is_nullable(layouts, data->elem) || mir_is_scalar(m, data->elem);
    case MK_STR: case MK_BYTES: case MK_TYPE: case MK_ALT: case MK_LIST:
        return false;
    }
    return false;
}

/* The byte offset of field `field` of the inline record `type_id` inside its memory image: its
 * fields' leaves in order, each at its natural offset. 0 when the leaves cannot be gathered. */
uint32_t mir_field_offset(MirLayouts *layouts, uint32_t type_id, uint32_t field) {
    const MirTypeDef *def = &layouts->module->type_defs[type_id];
    uint32_t total = 0;
    uint32_t start = 0;
    for (uint32_t k = 0; k < def->nfields; k++) {
        if (k == field) {
            start = total;
        }
        total += mir_leaves(layouts, def->fields[k].ty).len;
    }
    MirLeaf *all = calloc((size_t)total + 1, sizeof *all); /* owned, freed below */
    uint32_t *offsets = calloc((size_t)total + 1, sizeof *offsets); /* owned, freed below */
    uint32_t offset = 0;
    if (all != NULL && offsets != NULL) {
        uint32_t at = 0;
        for (uint32_t k = 0; k < def->nfields; k++) {
            const MirLeafSpan leaves = mir_leaves(layouts, def->fields[k].ty);
            for (uint32_t j = 0; j < leaves.len; j++) {
                all[at++] = leaves.ptr[j];
            }
        }
        (void)mir_mem_layout(all, total, offsets);
        offset = start < total ? offsets[start] : 0;
    }
    free(all);
    free(offsets);
    return offset;
}

/* The size in bytes of one element of list type `list`. */
uint32_t mir_list_elem_size(MirLayouts *layouts, MirTy list) {
    return mir_type_mem(layouts, mir_ty_data(layouts->module, list)->elem).size;
}

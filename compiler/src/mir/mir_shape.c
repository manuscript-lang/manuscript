/* MIR machine layout (layout.rs): the leaves of every type, their memory layout, the payload slots
 * of alternatives, closure objects, and the pointer and boolean flags the LLVM emitter reads.
 * Everything is computed on first ask and kept in the MirLayouts arena, which owns it. */
#include <stdlib.h>
#include <string.h>

#include "ms/mir_layout.h"

static const MirLeaf sh_no_leaves[1] = {MIR_LEAF_I64};
static const MirLeaf sh_one_word[1] = {MIR_LEAF_I64};
static const MirShape sh_empty_shape = {0};

/* Payload slots of an alternative are shared per leaf kind, widest first so each stays aligned. */
static const MirLeaf sh_slot_kinds[MIR_LEAF_COUNT] = {
    MIR_LEAF_I64, MIR_LEAF_F64, MIR_LEAF_F32, MIR_LEAF_N32, MIR_LEAF_U32,
    MIR_LEAF_N16, MIR_LEAF_U16, MIR_LEAF_N8,  MIR_LEAF_U8,  MIR_LEAF_I8};

uint32_t mir_leaf_size(MirLeaf leaf) {
    switch (leaf) {
    case MIR_LEAF_I8: case MIR_LEAF_N8: case MIR_LEAF_U8:
        return 1;
    case MIR_LEAF_N16: case MIR_LEAF_U16:
        return 2;
    case MIR_LEAF_N32: case MIR_LEAF_U32: case MIR_LEAF_F32:
        return 4;
    default:
        return 8;
    }
}

const char *mir_leaf_name(MirLeaf leaf) {
    static const char *const names[MIR_LEAF_COUNT] = {"i64", "f64", "i8",  "n8",  "n16",
                                                      "n32", "u8",  "u16", "u32", "f32"};
    return leaf < MIR_LEAF_COUNT ? names[leaf] : "?";
}

MirMemLayout mir_mem_layout(const MirLeaf *leaves, uint32_t count, uint32_t *offsets) {
    uint64_t offset = 0;
    uint32_t align = 1;
    for (uint32_t i = 0; i < count; i++) {
        uint32_t width = mir_leaf_size(leaves[i]);
        if (width > align) {
            align = width;
        }
        offset = (offset + width - 1) / width * width;
        if (offsets != NULL) {
            offsets[i] = (uint32_t)offset;
        }
        offset += width;
    }
    MirMemLayout layout = {.size = (uint32_t)((offset + align - 1) / align * align), .align = align};
    return layout;
}

void mir_layouts_init(MirLayouts *layouts, const MirModule *module) {
    memset(layouts, 0, sizeof *layouts);
    layouts->module = module;
    mir_boxing_init(&layouts->boxing, module);
    size_t ntypes = (size_t)module->types.len + 1, nalts = (size_t)module->nalts + 1;
    MsArena *arena = &layouts->arena;
    layouts->shapes = MS_NEW_N(arena, MirShape, ntypes);
    layouts->state = MS_NEW_N(arena, uint8_t, ntypes);
    layouts->pointer_marks = MS_NEW_N(arena, const bool *, ntypes);
    layouts->bool_marks = MS_NEW_N(arena, const bool *, ntypes);
    layouts->alt_fields = MS_NEW_N(arena, MirAltFields, nalts);
    layouts->alt_fields_state = MS_NEW_N(arena, uint8_t, nalts);
    memset(layouts->shapes, 0, sizeof(MirShape) * ntypes);
    memset(layouts->state, 0, ntypes);
    memset(layouts->pointer_marks, 0, sizeof(bool *) * ntypes);
    memset(layouts->bool_marks, 0, sizeof(bool *) * ntypes);
    memset(layouts->alt_fields, 0, sizeof(MirAltFields) * nalts);
    memset(layouts->alt_fields_state, 0, nalts);
}

void mir_layouts_free(MirLayouts *layouts) {
    mir_boxing_free(&layouts->boxing);
    ms_arena_free(&layouts->arena);
    memset(layouts, 0, sizeof *layouts);
}

bool mir_layouts_alt_boxed(MirLayouts *layouts, uint32_t alt) {
    return mir_boxing_alt(&layouts->boxing, alt);
}

bool mir_layouts_opt_boxed(MirLayouts *layouts, MirTy inner) {
    return mir_boxing_opt(&layouts->boxing, inner);
}

/* ---- leaf lists ---- */

/* Appends leaves to a scratch list, giving up (and marking the layouts failed) past the limit. */
static void sh_append(MirLayouts *layouts, MsBuf *list, const MirLeaf *leaves, size_t count) {
    if (list->len + count > MIR_LAYOUT_MAX_LEAVES) {
        layouts->failed = true;
        return;
    }
    ms_buf_put(list, leaves, count);
}

/* Moves a scratch list into the arena. */
static MirLeafSpan sh_keep(MirLayouts *layouts, const MsBuf *list) {
    MirLeafSpan span = {.ptr = sh_no_leaves, .len = 0};
    if (list->len == 0) {
        return span;
    }
    MirLeaf *copy = MS_NEW_N(&layouts->arena, MirLeaf, list->len);
    memcpy(copy, list->data, list->len);
    span.ptr = copy;
    span.len = (uint32_t)list->len;
    return span;
}

static MirShape sh_plain(MirLeafSpan leaves) {
    MirShape shape = {.leaves = leaves};
    return shape;
}

static MirShape sh_words(const MirLeaf *leaf, uint32_t count) {
    return sh_plain((MirLeafSpan){.ptr = leaf, .len = count});
}

static bool sh_is_map_or_set(const MirLayouts *layouts, const MirTyData *data) {
    (void)layouts;
    if (data->kind != MK_OBJ) {
        return false;
    }
    return data->obj_class == MIR_OBJ_COLLECTION;
}

bool mir_ty_is_map_or_set(const MirModule *module, MirTy ty) {
    const MirTyData *data = mir_ty_data(module, ty);
    if (data->kind != MK_OBJ) {
        return false;
    }
    return data->obj_class == MIR_OBJ_COLLECTION;
}

bool mir_type_field_boxed(const MirLayouts *layouts, MirTy field_ty) {
    return sh_is_map_or_set(layouts, mir_ty_data(layouts->module, field_ty));
}

bool mir_is_str_like(const MirLayouts *layouts, MirTy ty) {
    const MirTyData *data = mir_ty_data(layouts->module, ty);
    if (data->kind == MK_STR) {
        return true;
    }
    return data->kind == MK_OPT && mir_ty_data(layouts->module, data->elem)->kind == MK_STR;
}

bool mir_opt_is_nullable(MirLayouts *layouts, MirTy inner) {
    if (mir_boxing_opt(&layouts->boxing, inner)) {
        return true;
    }
    const MirTyData *data = mir_ty_data(layouts->module, inner);
    return data->kind == MK_FN || (data->kind == MK_OBJ && !sh_is_map_or_set(layouts, data));
}

/* ---- shapes ---- */

MirLeafSpan mir_leaves(MirLayouts *layouts, MirTy ty) {
    return mir_shape(layouts, ty)->leaves;
}

/* The leaves of each field of a record, one after another. */
static MirShape sh_record(MirLayouts *layouts, const MirField *fields, uint32_t count) {
    MsBuf list = {0};
    for (uint32_t i = 0; i < count; i++) {
        MirLeafSpan field = mir_leaves(layouts, fields[i].ty);
        sh_append(layouts, &list, field.ptr, field.len);
    }
    MirShape shape = sh_plain(sh_keep(layouts, &list));
    ms_buf_free(&list);
    return shape;
}

static MirShape sh_optional(MirLayouts *layouts, MirTy ty, MirTy inner) {
    static const MirLeaf two_words[2] = {MIR_LEAF_I64, MIR_LEAF_I64};
    if (mir_opt_is_nullable(layouts, inner)) {
        return sh_words(sh_one_word, 1);
    }
    if (mir_is_str_like(layouts, ty)) {
        return sh_words(two_words, 2);
    }
    MsBuf list = {0};
    const MirLeaf flag = MIR_LEAF_I8;
    sh_append(layouts, &list, &flag, 1);
    MirLeafSpan payload = mir_leaves(layouts, inner);
    sh_append(layouts, &list, payload.ptr, payload.len);
    MirShape shape = sh_plain(sh_keep(layouts, &list));
    ms_buf_free(&list);
    return shape;
}

/* The shape of a scalar or fixed-size type, or false when `kind` needs more than its tag. */
static bool sh_fixed(const MirLayouts *layouts, const MirTyData *data, MirShape *out) {
    static const MirLeaf scalar[MK_PTR + 1] = {
        [MK_BOOL] = MIR_LEAF_I8,   [MK_INT] = MIR_LEAF_I64,  [MK_FLOAT] = MIR_LEAF_F64,
        [MK_INT8] = MIR_LEAF_N8,   [MK_INT16] = MIR_LEAF_N16, [MK_INT32] = MIR_LEAF_N32,
        [MK_FLOAT32] = MIR_LEAF_F32, [MK_UINT8] = MIR_LEAF_U8, [MK_UINT16] = MIR_LEAF_U16,
        [MK_UINT32] = MIR_LEAF_U32, [MK_UINT64] = MIR_LEAF_I64, [MK_PTR] = MIR_LEAF_I64};
    static const MirLeaf words[MIR_MAP_WORDS] = {MIR_LEAF_I64, MIR_LEAF_I64, MIR_LEAF_I64,
                                                 MIR_LEAF_I64, MIR_LEAF_I64, MIR_LEAF_I64,
                                                 MIR_LEAF_I64};
    switch ((MirTyKind)data->kind) {
    case MK_VOID:
        *out = sh_words(sh_no_leaves, 0);
        return true;
    case MK_STR: case MK_IFACE:
        *out = sh_words(words, 2);
        return true;
    case MK_BYTES: case MK_LIST:
        *out = sh_words(words, 3);
        return true;
    case MK_FN:
        *out = sh_words(sh_one_word, 1);
        return true;
    case MK_OBJ:
        *out = sh_words(words, sh_is_map_or_set(layouts, data) ? MIR_MAP_WORDS : 1);
        return true;
    case MK_BOOL: case MK_INT: case MK_FLOAT: case MK_INT8: case MK_INT16: case MK_INT32:
    case MK_FLOAT32: case MK_UINT8: case MK_UINT16: case MK_UINT32: case MK_UINT64: case MK_PTR:
        *out = sh_words(&scalar[data->kind], 1);
        return true;
    case MK_TYPE: case MK_ALT: case MK_OPT:
        return false;
    }
    return false;
}

static uint32_t sh_slot_kind(MirLeaf leaf) {
    for (uint32_t k = 0; k < MIR_LEAF_COUNT; k++) {
        if (sh_slot_kinds[k] == leaf) {
            return k;
        }
    }
    return 0;
}

/* The leaves of every case's fields, one span per case. */
static MirLeafSpan *sh_case_leaves(MirLayouts *layouts, const MirAltDef *def) {
    MirLeafSpan *cases = MS_NEW_N(&layouts->arena, MirLeafSpan, def->ncases + 1);
    for (uint32_t c = 0; c < def->ncases; c++) {
        MirShape record = sh_record(layouts, def->cases[c].fields, def->cases[c].nfields);
        cases[c] = record.leaves;
    }
    return cases;
}

/* Fills in the block (tag, then each kind's slots) and the slot index of every payload leaf. */
static void sh_assign_slots(MirLayouts *layouts, const MirLeafSpan *cases, uint32_t ncases,
                            MirShape *shape) {
    uint32_t most[MIR_LEAF_COUNT] = {0};
    uint32_t total = 0;
    for (uint32_t c = 0; c < ncases; c++) {
        uint32_t seen[MIR_LEAF_COUNT] = {0};
        for (uint32_t i = 0; i < cases[c].len; i++) {
            uint32_t kind = sh_slot_kind(cases[c].ptr[i]);
            if (++seen[kind] > most[kind]) {
                most[kind] = seen[kind];
            }
        }
        total += cases[c].len;
    }
    MsBuf block = {0};
    const MirLeaf tag = MIR_LEAF_I64;
    sh_append(layouts, &block, &tag, 1);
    uint32_t next[MIR_LEAF_COUNT] = {0};
    for (uint32_t k = 0; k < MIR_LEAF_COUNT; k++) {
        next[k] = (uint32_t)block.len;
        for (uint32_t n = 0; n < most[k]; n++) {
            sh_append(layouts, &block, &sh_slot_kinds[k], 1);
        }
    }
    uint32_t *start = MS_NEW_N(&layouts->arena, uint32_t, ncases + 1);
    uint32_t *slots = MS_NEW_N(&layouts->arena, uint32_t, total + 1);
    uint32_t at = 0;
    for (uint32_t c = 0; c < ncases; c++) {
        uint32_t cursor[MIR_LEAF_COUNT];
        memcpy(cursor, next, sizeof cursor);
        start[c] = at;
        for (uint32_t i = 0; i < cases[c].len; i++) {
            slots[at++] = cursor[sh_slot_kind(cases[c].ptr[i])]++;
        }
    }
    start[ncases] = at;
    shape->slot_start = start;
    shape->slots = slots;
    shape->block = sh_keep(layouts, &block);
    ms_buf_free(&block);
}

static MirShape sh_alt_shape(MirLayouts *layouts, uint32_t alt) {
    const MirAltDef *def = &layouts->module->alts[alt];
    const MirLeafSpan *cases = sh_case_leaves(layouts, def);
    MirShape shape = {0};
    sh_assign_slots(layouts, cases, def->ncases, &shape);
    if (mir_boxing_alt(&layouts->boxing, alt)) {
        shape.alt = MIR_ALT_BOXED;
        shape.leaves = (MirLeafSpan){.ptr = sh_one_word, .len = 1};
    } else {
        shape.alt = MIR_ALT_INLINE;
        shape.leaves = shape.block;
        shape.block = (MirLeafSpan){.ptr = sh_no_leaves, .len = 0};
    }
    return shape;
}

static MirShape sh_compute(MirLayouts *layouts, MirTy ty) {
    const MirModule *module = layouts->module;
    const MirTyData *data = mir_ty_data(module, ty);
    MirShape shape = {0};
    if (sh_fixed(layouts, data, &shape)) {
        return shape;
    }
    switch ((MirTyKind)data->kind) {
    case MK_TYPE: {
        const MirTypeDef *def = &module->type_defs[data->id];
        if (def->indirect) {
            return sh_words(sh_one_word, 1);
        }
        return sh_record(layouts, def->fields, def->nfields);
    }
    case MK_OPT:
        return sh_optional(layouts, ty, data->elem);
    case MK_ALT:
        return sh_alt_shape(layouts, data->id);
    case MK_VOID: case MK_BOOL: case MK_INT: case MK_FLOAT: case MK_INT8: case MK_INT16:
    case MK_INT32: case MK_FLOAT32: case MK_UINT8: case MK_UINT16: case MK_UINT32:
    case MK_UINT64: case MK_STR: case MK_BYTES: case MK_PTR: case MK_LIST: case MK_OBJ:
    case MK_FN: case MK_IFACE:
        break;
    }
    return shape;
}

const MirShape *mir_shape(MirLayouts *layouts, MirTy ty) {
    if (ty >= layouts->module->types.len || layouts->depth >= MIR_LAYOUT_MAX_DEPTH) {
        layouts->failed = true;
        return &sh_empty_shape;
    }
    if (layouts->state[ty] != 0) {
        return &layouts->shapes[ty];
    }
    layouts->depth++;
    const MirTyData *data = mir_ty_data(layouts->module, ty);
    if (data->kind == MK_ALT && mir_boxing_alt(&layouts->boxing, data->id)) {
        /* A boxed alternative is one pointer; this also ends the recursion through its own fields. */
        layouts->shapes[ty] = sh_words(sh_one_word, 1);
        layouts->state[ty] = 1;
    }
    MirShape shape = sh_compute(layouts, ty);
    layouts->shapes[ty] = shape;
    layouts->state[ty] = 1;
    layouts->depth--;
    return &layouts->shapes[ty];
}

MirMemLayout mir_type_mem(MirLayouts *layouts, MirTy ty) {
    MirLeafSpan leaves = mir_leaves(layouts, ty);
    return mir_mem_layout(leaves.ptr, leaves.len, NULL);
}

/* ---- alternatives, blocks, closures ---- */

const MirAltFields *mir_alt_fields(MirLayouts *layouts, uint32_t alt) {
    static const MirAltFields none = {0};
    if (alt >= layouts->module->nalts) {
        layouts->failed = true;
        return &none;
    }
    if (layouts->alt_fields_state[alt] != 0) {
        return &layouts->alt_fields[alt];
    }
    const MirTyData key = {.kind = MK_ALT, .id = alt};
    MirTy ty = 0;
    if (!mir_ty_find(layouts->module, &key, &ty)) {
        layouts->failed = true;
        return &none;
    }
    const MirShape *shape = mir_shape(layouts, ty);
    const MirAltDef *def = &layouts->module->alts[alt];
    uint32_t nfields = 0;
    for (uint32_t c = 0; c < def->ncases; c++) {
        nfields += def->cases[c].nfields;
    }
    uint32_t *case_start = MS_NEW_N(&layouts->arena, uint32_t, def->ncases + 1);
    MirAltField *fields = MS_NEW_N(&layouts->arena, MirAltField, nfields + 1);
    uint32_t next = 0;
    for (uint32_t c = 0; c < def->ncases && shape->slot_start != NULL; c++) {
        case_start[c] = next;
        uint32_t at = shape->slot_start[c];
        for (uint32_t i = 0; i < def->cases[c].nfields; i++) {
            MirTy field_ty = def->cases[c].fields[i].ty;
            uint32_t width = mir_leaves(layouts, field_ty).len;
            fields[next++] = (MirAltField){.ty = field_ty, .leaves = shape->slots + at, .nleaves = width};
            at += width;
        }
    }
    case_start[def->ncases] = next;
    layouts->alt_fields[alt] = (MirAltFields){case_start, fields, def->ncases};
    layouts->alt_fields_state[alt] = 1;
    return &layouts->alt_fields[alt];
}

bool mir_alt_slot_source(const MirAltFields *fields, uint32_t case_index, uint32_t slot,
                         uint32_t *operand, uint32_t *leaf) {
    const uint32_t first = fields->case_start[case_index];
    for (uint32_t f = first; f < fields->case_start[case_index + 1]; f++) {
        for (uint32_t k = 0; k < fields->fields[f].nleaves; k++) {
            if (fields->fields[f].leaves[k] == slot) {
                *operand = f - first;
                *leaf = k;
                return true;
            }
        }
    }
    return false;
}

MirLeafSpan mir_type_block(MirLayouts *layouts, uint32_t type_id) {
    const MirTypeDef *def = &layouts->module->type_defs[type_id];
    MsBuf list = {0};
    for (uint32_t i = 0; i < def->nfields; i++) {
        if (mir_type_field_boxed(layouts, def->fields[i].ty)) {
            sh_append(layouts, &list, sh_one_word, 1);
        } else {
            MirLeafSpan field = mir_leaves(layouts, def->fields[i].ty);
            sh_append(layouts, &list, field.ptr, field.len);
        }
    }
    MirLeafSpan span = sh_keep(layouts, &list);
    ms_buf_free(&list);
    return span;
}

bool mir_record_block(MirLayouts *layouts, uint32_t type_id, MirRecordBlock *out) {
    *out = (MirRecordBlock){.def = &layouts->module->type_defs[type_id]};
    out->leaves = mir_type_block(layouts, type_id);
    out->offsets = calloc((size_t)out->leaves.len + 1, sizeof *out->offsets);
    out->starts = calloc((size_t)out->def->nfields + 1, sizeof *out->starts);
    out->boxed = calloc((size_t)out->def->nfields + 1, sizeof *out->boxed);
    if (out->offsets == NULL || out->starts == NULL || out->boxed == NULL) {
        mir_record_block_free(out);
        return false;
    }
    out->size = mir_mem_layout(out->leaves.ptr, out->leaves.len, out->offsets).size;
    uint32_t at = 0;
    for (uint32_t k = 0; k < out->def->nfields; k++) {
        out->starts[k] = at;
        out->boxed[k] = mir_type_field_boxed(layouts, out->def->fields[k].ty);
        at += out->boxed[k] ? 1 : mir_leaves(layouts, out->def->fields[k].ty).len;
    }
    return true;
}

void mir_record_block_free(MirRecordBlock *block) {
    free(block->offsets);
    free(block->starts);
    free(block->boxed);
    *block = (MirRecordBlock){0};
}

bool mir_opt_has_flag(MirLayouts *layouts, MirTy opt) {
    const MirTy inner = mir_ty_data(layouts->module, opt)->elem;
    return !mir_layouts_opt_boxed(layouts, inner) && !mir_opt_is_nullable(layouts, inner) &&
           !mir_is_str_like(layouts, opt);
}

bool mir_boxed_block_size(MirLayouts *layouts, MirTy ty, uint32_t *size) {
    const MirShape *shape = mir_shape(layouts, ty);
    if (shape->alt != MIR_ALT_BOXED) {
        return false;
    }
    *size = mir_mem_layout(shape->block.ptr, shape->block.len, NULL).size;
    return true;
}

MirClosureLayout mir_closure_layout(MirLayouts *layouts, const MirFunc *f) {
    uint32_t count = f->kind == MFK_CLOSURE ? f->ncaptures : 0;
    MirCaptureSlot *slots = MS_NEW_N(&layouts->arena, MirCaptureSlot, count + 1);
    uint64_t offset = MIR_CLOSURE_CAPTURES_OFFSET;
    for (uint32_t i = 0; i < count; i++) {
        MirLeafSpan leaves = mir_leaves(layouts, f->captures[i]);
        MirMemLayout mem = mir_mem_layout(leaves.ptr, leaves.len, NULL);
        offset = (offset + mem.align - 1) / mem.align * mem.align;
        slots[i] = (MirCaptureSlot){.ty = f->captures[i], .offset = (uint32_t)offset, .leaves = leaves};
        offset += mem.size;
        if (offset > UINT32_MAX / 2) {
            layouts->failed = true;
            offset = UINT32_MAX / 2;
        }
    }
    MirClosureLayout layout = {.captures = slots, .ncaptures = count,
                               .size = (uint32_t)((offset + 7) / 8 * 8)};
    return layout;
}

/* ---- pointer and boolean flags ---- */

static void sh_flags(MirLayouts *layouts, MirTy ty, bool pointers, MsBuf *out);

static void sh_flag_run(MsBuf *out, bool value, uint32_t count) {
    for (uint32_t i = 0; i < count; i++) {
        ms_buf_putc(out, value ? '\1' : '\0');
    }
}

static void sh_flags_of_fields(MirLayouts *layouts, const MirField *fields, uint32_t count,
                               bool pointers, MsBuf *out) {
    for (uint32_t i = 0; i < count; i++) {
        sh_flags(layouts, fields[i].ty, pointers, out);
    }
}

/* Appends one flag per register leaf of `ty`: a pointer (when `pointers`) or a boolean. */
static void sh_flags_inner(MirLayouts *layouts, MirTy ty, bool pointers, MsBuf *out) {
    const MirModule *module = layouts->module;
    const MirTyData *data = mir_ty_data(module, ty);
    uint32_t width = mir_leaves(layouts, ty).len;
    bool object = data->kind == MK_OBJ && !sh_is_map_or_set(layouts, data);
    bool indirect = data->kind == MK_TYPE && module->type_defs[data->id].indirect;
    bool nullable = data->kind == MK_OPT && mir_opt_is_nullable(layouts, data->elem);
    bool boxed = data->kind == MK_ALT && mir_boxing_alt(&layouts->boxing, data->id);
    if (data->kind == MK_BOOL) {
        sh_flag_run(out, !pointers, 1);
    } else if (data->kind == MK_PTR || data->kind == MK_FN || object || indirect || nullable ||
               boxed) {
        sh_flag_run(out, pointers, 1);
    } else if (data->kind == MK_IFACE) {
        sh_flag_run(out, pointers, 2);
    } else if (data->kind == MK_BYTES || data->kind == MK_LIST) {
        sh_flag_run(out, pointers, 1);
        sh_flag_run(out, false, 2);
    } else if (data->kind == MK_TYPE) {
        const MirTypeDef *def = &module->type_defs[data->id];
        sh_flags_of_fields(layouts, def->fields, def->nfields, pointers, out);
    } else if (data->kind == MK_OPT && !mir_is_str_like(layouts, ty)) {
        sh_flag_run(out, !pointers, 1);
        sh_flags(layouts, data->elem, pointers, out);
    } else {
        sh_flag_run(out, false, width);
    }
}

static void sh_flags(MirLayouts *layouts, MirTy ty, bool pointers, MsBuf *out) {
    if (layouts->depth >= MIR_LAYOUT_MAX_DEPTH) {
        layouts->failed = true;
        return;
    }
    layouts->depth++;
    sh_flags_inner(layouts, ty, pointers, out);
    layouts->depth--;
}

static const bool *sh_marks(MirLayouts *layouts, MirTy ty, bool pointers) {
    static const bool none[1] = {false};
    if (ty >= layouts->module->types.len) {
        layouts->failed = true;
        return none;
    }
    const bool **cache = pointers ? layouts->pointer_marks : layouts->bool_marks;
    if (cache[ty] != NULL) {
        return cache[ty];
    }
    MsBuf flags = {0};
    sh_flags(layouts, ty, pointers, &flags);
    bool *kept = MS_NEW_N(&layouts->arena, bool, flags.len + 1);
    for (size_t i = 0; i < flags.len; i++) {
        kept[i] = flags.data[i] != 0;
    }
    ms_buf_free(&flags);
    cache[ty] = kept;
    return kept;
}

const bool *mir_pointer_leaves(MirLayouts *layouts, MirTy ty) {
    return sh_marks(layouts, ty, true);
}

const bool *mir_bool_leaves(MirLayouts *layouts, MirTy ty) {
    return sh_marks(layouts, ty, false);
}

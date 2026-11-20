/* Value classes for the ownership pass (ms/ownership.h): `classify.rs`'s `Classifier::class`.
 *
 * A type's class is the largest class of what it holds. A nominal type holds its fields and the
 * payloads of its cases; a type that reaches itself again is boxed and moves. Types are interned,
 * so "the same instance" is an integer compare and a result is kept per type.
 *
 * A result that stopped at an ancestor still being classified could differ from the type's own
 * class (the ancestor's other fields were not read yet), so it is not kept; see `ClassWalk.floor`. */
#include <stdlib.h>
#include <string.h>

#include "ms/methods.h"
#include "ms/ownership.h"

enum { CLASS_MAX_NESTING = 64, CLASS_UNKNOWN = 0xff };

struct MsClassifier {
    MsCheck *check; /* borrowed */
    uint8_t *known; /* owned: by MsTy, an MsClass or CLASS_UNKNOWN */
    uint32_t known_capacity;
    MsNameMap closeable;   /* owned: type identities that close themselves */
    MsNameMap owned_close; /* owned: interface identities with a consuming close */
    MsSym close_name;      /* the name of the operation `Closeable` declares, MS_NONE until looked up */
    bool close_known;
};

/* One classification: the nominal types being classified (innermost last), and the outermost
 * stack position a cut-off reached. A type at position `p` may keep its result when `floor >= p`;
 * `floor` 0 means the nesting limit was hit, which depends on where the walk started. */
typedef struct ClassWalk {
    MsTy stack[CLASS_MAX_NESTING + 1];
    uint32_t depth;
    uint32_t floor;
} ClassWalk;

MsClassifier *ms_classifier_new(MsCheck *check) {
    MsClassifier *classifier = calloc(1, sizeof *classifier);
    if (classifier == NULL) {
        ms_oom();
    }
    classifier->check = check;
    classifier->close_name = MS_NONE;
    return classifier;
}

void ms_classifier_free(MsClassifier *classifier) {
    if (classifier == NULL) {
        return;
    }
    free(classifier->known);
    ms_map_free(&classifier->closeable);
    ms_map_free(&classifier->owned_close);
    free(classifier);
}

void ms_classifier_mark_closeable(MsClassifier *classifier, MsSym type_id) {
    (void)ms_map_add(&classifier->closeable, type_id, 1);
}

/* The name of the one operation the `Closeable` interface declares: what closes a value is read from
 * the declaration, not spelled here. MS_NONE when the table is not loaded. */
static MsSym close_name(MsClassifier *classifier) {
    if (classifier->close_known) {
        return classifier->close_name;
    }
    const MsCheck *check = classifier->check;
    const MsTyTable *tys = &check->tys;
    for (MsSymId sym = 0; sym < check->syms.count && classifier->close_name == MS_NONE; sym++) {
        const MsTy ty = check->syms.ty[sym];
        const MsDecl *decl = check->syms.decl[sym];
        if (ty != MS_TY_NONE && ms_ty_is(tys, ty, MS_BI_CLOSEABLE) && decl != NULL && decl->kind == MS_D_INTERFACE &&
            decl->u.iface.methods.len == 1) {
            classifier->close_name = decl->u.iface.methods.ptr[0]->func.name;
        }
    }
    classifier->close_known = true;
    return classifier->close_name;
}

/* `Method::closes`: a `Closeable` implementation, or a type's own `close()` that returns
 * `Void!`, which satisfies `Closeable` by shape. */
static bool row_closes(MsClassifier *classifier, const MsMethods *rows, uint32_t i) {
    const MsCheck *check = classifier->check;
    const MsTyTable *tys = &check->tys;
    if (rows->contract[i] != MS_TY_NONE && ms_ty_is(tys, rows->contract[i], MS_BI_CLOSEABLE)) {
        return true;
    }
    const MsFunc *decl = rows->decl[i];
    if (!rows->inherent[i] || decl == NULL || decl->name != close_name(classifier) ||
        tys->nparams[rows->ty[i]] != 0) {
        return false;
    }
    const MsTy result = tys->result[rows->ty[i]];
    return ms_ty_is(tys, result, MS_BI_RESULT) && tys->nargs[result] == 2 &&
           ms_ty_is(tys, ms_ty_args(tys, result)[0], MS_BI_VOID) && ms_ty_is(tys, ms_ty_args(tys, result)[1], MS_BI_ERROR);
}

void ms_classifier_mark_methods(MsClassifier *classifier, const MsMethods *rows) {
    for (uint32_t i = 0; rows != NULL && i < rows->count; i++) {
        if (row_closes(classifier, rows, i)) {
            ms_classifier_mark_closeable(classifier, classifier->check->tys.id[rows->receiver[i]]);
        }
    }
}

void ms_classifier_mark_owned_close(MsClassifier *classifier, MsSym interface_id) {
    (void)ms_map_add(&classifier->owned_close, interface_id, 1);
}

static MsClass larger(MsClass a, MsClass b) {
    return a > b ? a : b;
}

/* The kept result for `type`, or CLASS_UNKNOWN. Types interned since the last call are unknown. */
static uint8_t known_class(MsClassifier *classifier, MsTy type) {
    return type < classifier->known_capacity ? classifier->known[type] : CLASS_UNKNOWN;
}

static void keep_class(MsClassifier *classifier, MsTy type, MsClass class) {
    if (type >= classifier->known_capacity) {
        const uint32_t capacity = ms_capacity_for(classifier->known_capacity, classifier->check->tys.count);
        classifier->known = ms_array_resize(classifier->known, capacity, sizeof *classifier->known);
        memset(classifier->known + classifier->known_capacity, CLASS_UNKNOWN, capacity - classifier->known_capacity);
        classifier->known_capacity = capacity;
    }
    classifier->known[type] = (uint8_t)class;
}

static bool is_marked(const MsNameMap *set, const MsTyTable *tys, MsTy type) {
    return ms_map_get(set, tys->id[type]) != MS_NONE;
}

static MsClass class_in(MsClassifier *classifier, MsTy type, ClassWalk *walk);

/* A type variable is a resource when a bound is `Closeable`. */
static MsClass variable_class(MsClassifier *classifier, MsTy type) {
    const MsVarInfo *info = ms_var_info(classifier->check, type);
    for (uint32_t i = 0; i < info->nbounds; i++) {
        if (ms_ty_is(&classifier->check->tys, info->bounds[i], MS_BI_CLOSEABLE)) {
            return MS_CLASS_RESOURCE;
        }
    }
    return MS_CLASS_MOVE;
}

/* A native holding values (`List[T]`, `Map[K, V]`) owns them, so it moves, and is a resource when
 * what it holds is. A plain-word native (`Decimal`) copies, unless a collection holds it. */
static MsClass native_class(MsClassifier *classifier, MsTy type, ClassWalk *walk) {
    const MsTyTable *tys = &classifier->check->tys;
    bool held = false;
    for (MsTy current = type;;) {
        if (is_marked(&classifier->closeable, tys, current)) {
            return MS_CLASS_RESOURCE;
        }
        if (ms_ty_is(tys, current, MS_BI_DECIMAL)) {
            return held ? MS_CLASS_MOVE : MS_CLASS_COPY;
        }
        const uint32_t element_index = ms_ty_is(tys, current, MS_BI_MAP) ? 1 : 0;
        const bool holds = ms_ty_is(tys, current, MS_BI_LIST) || ms_ty_is(tys, current, MS_BI_MAP);
        if (!holds || tys->nargs[current] <= element_index) {
            return MS_CLASS_MOVE;
        }
        const MsTy element = ms_ty_args(tys, current)[element_index];
        if (ms_ty_kind(tys, element) != MS_K_NATIVE) {
            return class_in(classifier, element, walk) == MS_CLASS_RESOURCE ? MS_CLASS_RESOURCE : MS_CLASS_MOVE;
        }
        current = element;
        held = true;
    }
}

/* The class of one field or payload slot of `type`, with its type arguments substituted. */
static MsClass slot_class(MsClassifier *classifier, MsTy slot, const MsTySubst *subst, ClassWalk *walk) {
    MsCheck *check = classifier->check;
    MsArena scratch = {0};
    const MsTy substituted = subst->count == 0 ? slot : ms_ty_subst(&check->tys, &scratch, slot, subst);
    ms_arena_free(&scratch);
    return class_in(classifier, substituted, walk);
}

static MsClass nominal_fields_class(MsClassifier *classifier, MsTy type, ClassWalk *walk) {
    MsCheck *check = classifier->check;
    if (check->tys.def[type] == 0) {
        return ms_ty_kind(&check->tys, type) == MS_K_TYPE ? MS_CLASS_MOVE : MS_CLASS_COPY;
    }
    /* Copied: classifying a slot may add definition rows and move the table. */
    const MsDef def_row = *ms_def(check, check->tys.def[type] - 1);
    const MsDef *def = &def_row;
    const uint32_t bound = def->nvars < check->tys.nargs[type] ? def->nvars : check->tys.nargs[type];
    const MsTySubst subst = {def->vars, ms_ty_args(&check->tys, type), bound};
    /* A type is a container of its fields and has one owner whatever they are; an alternative of
     * primitives is a primitive. */
    MsClass class = ms_ty_kind(&check->tys, type) == MS_K_TYPE ? MS_CLASS_MOVE : MS_CLASS_COPY;
    for (uint32_t i = 0; i < def->nfields; i++) {
        class = larger(class, slot_class(classifier, def->fields[i].ty, &subst, walk));
    }
    for (uint32_t i = 0; i < def->ncases; i++) {
        for (uint32_t j = 0; j < def->cases[i].nfields; j++) {
            class = larger(class, slot_class(classifier, def->cases[i].fields[j].ty, &subst, walk));
        }
    }
    return class;
}

static MsClass nominal_class(MsClassifier *classifier, MsTy type, ClassWalk *walk) {
    if (is_marked(&classifier->closeable, &classifier->check->tys, type)) {
        return MS_CLASS_RESOURCE;
    }
    /* A type containing itself is boxed: it cannot be copied implicitly. */
    if (walk->depth > CLASS_MAX_NESTING) {
        walk->floor = 0;
        return MS_CLASS_MOVE;
    }
    for (uint32_t i = 0; i < walk->depth; i++) {
        if (walk->stack[i] == type) {
            walk->floor = i < walk->floor ? i : walk->floor;
            return MS_CLASS_MOVE;
        }
    }
    walk->stack[walk->depth++] = type;
    const MsClass class = nominal_fields_class(classifier, type, walk);
    walk->depth--;
    return class;
}

/* `declares_owned_close`: the interface declares `move fn close()`, so a value of it owns what it
 * was made from. */
static bool declares_owned_close(MsClassifier *classifier, MsTy type) {
    const MsCheck *check = classifier->check;
    const MsTyTable *tys = &check->tys;
    if (is_marked(&classifier->owned_close, tys, type)) {
        return true;
    }
    const MsOperations *ops = check->methods == NULL || tys->def[type] == 0
                                  ? NULL
                                  : ms_interface_operations(check->methods, tys->def[type] - 1);
    for (uint32_t i = 0; ops != NULL && i < ops->count; i++) {
        if (ops->items[i].decl->consuming && ops->items[i].name == close_name(classifier)) {
            return true;
        }
    }
    return false;
}

static MsClass compute_class(MsClassifier *classifier, MsTy type, ClassWalk *walk) {
    const MsTyTable *tys = &classifier->check->tys;
    switch (ms_ty_kind(tys, type)) {
    case MS_K_PRIMITIVE:
        return ms_ty_is(tys, type, MS_BI_STRING) ? MS_CLASS_MOVE : MS_CLASS_COPY;
    case MS_K_INVALID:
    case MS_K_INFERRED:
        return MS_CLASS_COPY;
    case MS_K_VARIABLE:
        return variable_class(classifier, type);
    case MS_K_CONTRACT:
        return ms_ty_is(tys, type, MS_BI_CLOSEABLE) || declares_owned_close(classifier, type)
                   ? MS_CLASS_RESOURCE
                   : MS_CLASS_MOVE;
    case MS_K_FUNCTION:
        return MS_CLASS_MOVE;
    case MS_K_NATIVE:
        return native_class(classifier, type, walk);
    case MS_K_TYPE:
    case MS_K_ALTERNATIVE:
        return nominal_class(classifier, type, walk);
    }
    return MS_CLASS_MOVE;
}

static MsClass class_in(MsClassifier *classifier, MsTy type, ClassWalk *walk) {
    const uint8_t kept = known_class(classifier, type);
    if (kept != CLASS_UNKNOWN) {
        return (MsClass)kept;
    }
    const uint32_t outer_floor = walk->floor;
    walk->floor = UINT32_MAX;
    const MsClass class = compute_class(classifier, type, walk);
    if (walk->floor >= walk->depth) {
        keep_class(classifier, type, class);
    }
    walk->floor = walk->floor < outer_floor ? walk->floor : outer_floor;
    return class;
}

MsClass ms_classify(MsClassifier *classifier, MsTy type) {
    ClassWalk walk = {.depth = 0, .floor = UINT32_MAX};
    return class_in(classifier, type, &walk);
}

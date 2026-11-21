/* compiler/own/class.c: value classes of types. */
#include "compiler/own/class.h"

#define MS_CLASS_ACTIVE 255

MsClassifier ms_class_new(MsCheckProgram *program) {
  return (MsClassifier){.program = program};
}

void ms_class_free(MsClassifier *classifier) {
  ms_class_memo_free(&classifier->memo);
  ms_ty_list_free(&classifier->closeable);
}

void ms_class_mark_closeable(MsClassifier *classifier, MsTy ty) {
  ms_ty_list_push(&classifier->closeable, ty);
}

static bool is_closeable(const MsClassifier *classifier, MsTy ty) {
  for (size_t index = 0; index < classifier->closeable.len; index++) {
    if (classifier->closeable.ptr[index] == ty) {
      return true;
    }
  }
  return false;
}

static MsClass max_class(MsClass a, MsClass b) {
  return a > b ? a : b;
}

/* The method declared at `ref`, searched in the interfaces of its module. */
static const MsMethod *find_method(const MsCheckProgram *program, MsDeclRef ref) {
  if (ref.file >= program->modules.len) {
    return NULL;
  }
  const MsModule *tree = program->modules.ptr[ref.file].tree;
  for (uint32_t index = 0; index < tree->ndecls; index++) {
    const MsDecl *decl = tree->decls[index];
    if (decl->kind != MS_D_INTERFACE) {
      continue;
    }
    for (uint32_t at = 0; at < decl->u.iface.methods.len; at++) {
      if (decl->u.iface.methods.ptr[at]->id == ref.node) {
        return decl->u.iface.methods.ptr[at];
      }
    }
  }
  return NULL;
}

/* Whether the interface declares `move fn close()`: a value of it owns what it was made from. */
static bool declares_owned_close(const MsCheckProgram *program, MsTy ty) {
  const MsDef *def = ms_defs_get(&program->defs, program->types.rows.ptr[ty].def);
  for (size_t index = 0; index < def->operations.len; index++) {
    const MsOperation *operation = &def->operations.ptr[index];
    if (!ms_span_is_text(ms_names_span(program->names, operation->name), "close")) {
      continue;
    }
    const MsMethod *method = find_method(program, operation->decl);
    if (method != NULL && method->consuming) {
      return true;
    }
  }
  return false;
}

static MsClass variable_class(MsClassifier *classifier, MsTy ty) {
  MsTyTable *table = &classifier->program->types;
  const MsTyVariable *variable = ms_ty_variable(table, ty);
  for (size_t index = 0; variable != NULL && index < variable->bounds.len; index++) {
    if (ms_ty_is(table, variable->bounds.ptr[index], MS_BUILTIN_Closeable)) {
      return MS_CLASS_RESOURCE;
    }
  }
  return MS_CLASS_MOVE;
}

static MsClass class_in(MsClassifier *classifier, MsTy ty);

/* A native: a collection holds its elements, so it is a Resource when they are and Move otherwise. A
 * Decimal is a plain word unless held in a collection. */
static MsClass native_class(MsClassifier *classifier, MsTy ty) {
  const MsTyTable *table = &classifier->program->types;
  bool held = false;
  for (MsTy current = ty;;) {
    if (is_closeable(classifier, current)) {
      return MS_CLASS_RESOURCE;
    }
    if (ms_ty_is(table, current, MS_BUILTIN_Decimal)) {
      return held ? MS_CLASS_MOVE : MS_CLASS_COPY;
    }
    const size_t element_at = ms_ty_is(table, current, MS_BUILTIN_Map) ? 1 : 0;
    const bool collection = ms_ty_is(table, current, MS_BUILTIN_List) || element_at == 1;
    if (!collection || ms_ty_arg_count(table, current) <= element_at) {
      return MS_CLASS_MOVE;
    }
    const MsTy element = ms_ty_args(table, current)[element_at];
    if (ms_ty_kind(table, element) != MS_TY_NATIVE) {
      return class_in(classifier, element) == MS_CLASS_RESOURCE ? MS_CLASS_RESOURCE : MS_CLASS_MOVE;
    }
    current = element;
    held = true;
  }
}

/* The class of one field or payload slot of `ty`, with the type's arguments substituted. */
static MsClass slot_class(MsClassifier *classifier, const MsDef *def, MsTy ty, MsTy slot) {
  MsTyTable *table = &classifier->program->types;
  const size_t count = def->variables.len < ms_ty_arg_count(table, ty) ? def->variables.len
                                                                       : ms_ty_arg_count(table, ty);
  const MsTy substituted = ms_ty_subst(table, slot, def->variables.ptr, ms_ty_args(table, ty), count);
  return class_in(classifier, substituted);
}

static MsClass nominal_class(MsClassifier *classifier, MsTy ty) {
  if (is_closeable(classifier, ty)) {
    return MS_CLASS_RESOURCE;
  }
  const MsDef *def = ms_defs_get(&classifier->program->defs, classifier->program->types.rows.ptr[ty].def);
  /* A type is a container of its fields and has one owner whatever they are; an alternative of primitives
   * is a primitive. */
  MsClass class = ms_ty_kind(&classifier->program->types, ty) == MS_TY_TYPE ? MS_CLASS_MOVE : MS_CLASS_COPY;
  for (size_t index = 0; index < def->fields.len; index++) {
    class = max_class(class, slot_class(classifier, def, ty, def->fields.ptr[index].ty));
  }
  for (size_t index = 0; index < def->cases.len; index++) {
    const MsTyCase *alternative = &def->cases.ptr[index];
    for (size_t at = 0; at < alternative->fields.len; at++) {
      class = max_class(class, slot_class(classifier, def, ty, alternative->fields.ptr[at].ty));
    }
  }
  return class;
}

static MsClass compute(MsClassifier *classifier, MsTy ty) {
  const MsTyTable *table = &classifier->program->types;
  switch (ms_ty_kind(table, ty)) {
  case MS_TY_PRIMITIVE:
    return ms_ty_is(table, ty, MS_BUILTIN_String) ? MS_CLASS_MOVE : MS_CLASS_COPY;
  case MS_TY_INVALID:
  case MS_TY_INFERRED:
    return MS_CLASS_COPY;
  case MS_TY_VARIABLE:
    return variable_class(classifier, ty);
  case MS_TY_CONTRACT:
    return ms_ty_is(table, ty, MS_BUILTIN_Closeable) || declares_owned_close(classifier->program, ty)
               ? MS_CLASS_RESOURCE
               : MS_CLASS_MOVE;
  case MS_TY_FUNCTION:
    return MS_CLASS_MOVE;
  case MS_TY_NATIVE:
    return native_class(classifier, ty);
  case MS_TY_TYPE:
  case MS_TY_ALTERNATIVE:
    return nominal_class(classifier, ty);
  }
  return MS_CLASS_MOVE;
}

static uint8_t *memo_slot(MsClassifier *classifier, MsTy ty) {
  const size_t rows = classifier->program->types.rows.len;
  const size_t known = classifier->memo.len;
  if (known < rows) {
    uint8_t *added = ms_class_memo_extend(&classifier->memo, rows - known);
    for (size_t index = 0; index < rows - known; index++) {
      added[index] = 0;
    }
  }
  return &classifier->memo.ptr[ty];
}

static MsClass class_in(MsClassifier *classifier, MsTy ty) {
  uint8_t *slot = memo_slot(classifier, ty);
  if (*slot == MS_CLASS_ACTIVE) {
    classifier->cuts++; /* a type containing itself is boxed: it cannot be copied implicitly */
    return MS_CLASS_MOVE;
  }
  if (*slot != 0) {
    return (MsClass)(*slot - 1);
  }
  const uint32_t cuts_before = classifier->cuts;
  *slot = MS_CLASS_ACTIVE;
  classifier->depth++;
  const MsClass class = compute(classifier, ty);
  classifier->depth--;
  slot = memo_slot(classifier, ty);
  *slot = classifier->depth == 0 || classifier->cuts == cuts_before ? (uint8_t)(class + 1) : 0;
  return class;
}

MsClass ms_class_of(MsClassifier *classifier, MsTy ty) {
  return class_in(classifier, ty);
}

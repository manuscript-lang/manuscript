/* compiler/mir/mir_glue.h: the helper functions every back end would otherwise write for itself.
 *
 * For each type whose drop is a walk of its fields (a record, an alternative, an optional, a list or bytes, a
 * map or set, an interface) the pass makes a drop function, and a clone function for the types that are cloned;
 * for each type a descriptor points at, a slot drop and a slot copy; for each interface payload, a block drop
 * and a block clone; and for each closure object, drop and clone entries. The emitter calls these functions
 * instead of writing a body of its own, so every back end releases the same cases and fields. Names carry the
 * module's function count (`ms.glue.mir.<n>.<kind>`), so one module always gets the same names.
 *
 * Ownership: a MirGlue owns its two lists (mir_glue_free); the functions it names live in the module. */
#ifndef MS_COMPILER_MIR_MIR_GLUE_H
#define MS_COMPILER_MIR_MIR_GLUE_H

#include "compiler/mir/mir.h"

typedef enum MirGlueKind {
  MG_DROP,
  MG_CLONE,
  MG_CLOSURE_DROP,
  MG_CLOSURE_DROP_FRAMED,
  MG_CLOSURE_DROP_FROM,
  MG_CLOSURE_CLONE,
  MG_BLOCK_DROP,
  MG_BLOCK_CLONE,
  MG_SLOT_DROP,
  MG_SLOT_COPY
} MirGlueKind;

/* One made function. `ty` is the type it works on (MIR_VOID for the closure kinds, which carry the closure
 * function in `a` and, for MG_CLOSURE_DROP_FROM, the capture in `b`). */
typedef struct MirGlueEntry {
  uint8_t kind; /* a MirGlueKind */
  uint32_t a, b;
  MirTy ty;
  uint32_t func;
} MirGlueEntry;

MS_LIST_DEFINE(MirGlueEntryList, mir_glue_entry_list, MirGlueEntry)

/* Everything the glue passes made. A zeroed MirGlue is empty. */
typedef struct MirGlue {
  MirGlueEntryList entries;
  MirIdList bodies; /* the bodies the deep-recursion wrappers call */
} MirGlue;

void mir_glue_free(MirGlue *glue);

/* The function made for `kind` of `ty` (and closure `a`, capture `b`), or MIR_NONE. */
uint32_t mir_glue_find(const MirGlue *glue, MirGlueKind kind, MirTy ty, uint32_t a, uint32_t b);

/* Makes the missing glue for what the module's functions drop, clone and name. Returns whether it made any;
 * the new functions may ask for more, so a caller runs it until it returns false. */
bool mir_glue(MirModule *module, MirGlue *glue);

/* The function `(list, from)` behind `list.release` for list type `ty`: it drops the elements from index `from`
 * (a negative one counts from the start) and frees the block of an owned list (capacity not 0). Its element
 * drops are `drop` ops, which lower_ops rewrites to calls of the element's drop glue. */
uint32_t mir_glue_list_release(MirModule *module, MirTy ty);

#endif

/* compiler/lower/lower_internal.h: the state the lowering files share. */
#ifndef MS_COMPILER_LOWER_LOWER_INTERNAL_H
#define MS_COMPILER_LOWER_LOWER_INTERNAL_H

#include "compiler/lower/lower.h"
#include "compiler/mir/mir_builder.h"

MS_MAP_DEFINE(LowerTyMap, lower_ty_map, uint32_t, uint32_t, ms_hash_u32_key, ms_equal_u32_key)

/* One function to lower: a declaration with the type arguments of one use, and the MIR function reserved
 * for it so calls can name it before its body exists. */
typedef struct LowerInstance {
  MsSymbolId symbol;
  const MsTy *args; /* in the program arena */
  uint32_t nargs;
  uint32_t func;    /* the reserved MIR function */
  bool lowered;
} LowerInstance;

MS_LIST_DEFINE(LowerInstanceList, lower_instance_list, LowerInstance)

typedef struct Lower {
  MsCheckProgram *program;
  MirModule *module;
  MsStrBuild *error;
  LowerTyMap types;            /* type (after substitution) -> MIR type */
  MsNames instance_keys;       /* instance key text -> dense id, the index into `instances` */
  LowerInstanceList instances;
} Lower;

/* The type variables being replaced while one instance is lowered, and what replaces them. */
typedef struct LowerSubst {
  const MsTy *vars;
  const MsTy *args;
  size_t count;
} LowerSubst;

#define lower_fail(cx, ...) (ms_strbuild_printf((cx)->error, __VA_ARGS__), false)

/* ---- types (lower_types.c) ---- */

/* The MIR type of `ty` once `subst` is applied; MIR_VOID after reporting when the type has no MIR form. */
MirTy lower_type(Lower *cx, const LowerSubst *subst, MsTy ty);

/* The source text of `ty` after substitution, as MIR names it (`Box[Int]`). */
void lower_type_text(Lower *cx, const LowerSubst *subst, MsTy ty, MsStrBuild *out);

#endif

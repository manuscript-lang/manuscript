/* compiler/mir/mir_desc.h: how the descriptor of a type is made. The runtime reads descriptors to drop, copy,
 * compare and hash values it only knows by address (collection elements, task results). */
#ifndef MS_COMPILER_MIR_MIR_DESC_H
#define MS_COMPILER_MIR_MIR_DESC_H

#include "compiler/mir/mir_layout.h"

/* The `kind` word of a descriptor (the runtime's MsKind). */
enum { MIR_DESC_SHARED = 5, MIR_DESC_POD = 6, MIR_DESC_LIST = 7, MIR_DESC_MAP = 8, MIR_DESC_SET = 9,
       MIR_DESC_CUSTOM = 10 };

/* The descriptor's byte offsets (MsTypeDesc): size and alignment, kind, then the addresses. */
enum { MIR_DESC_BYTES = 64, MIR_DESC_INNER0 = 16, MIR_DESC_INNER1 = 24, MIR_DESC_DROP = 32,
       MIR_DESC_COPY = 40, MIR_DESC_EQ = 48, MIR_DESC_HASH = 56 };

/* The scope of a key whose type is plain bits whatever it holds (a forgotten value). */
#define MIR_FORGOTTEN_SCOPE ((UINT32_C(1) << (32 - MIR_SCOPE_SHIFT)) - 1)

typedef struct MirDescPlan {
  MsSpan runtime;    /* a descriptor the runtime defines, else empty */
  uint32_t size, align, kind;
  MirTy inner[2];    /* element, or key and value, under the scope of `key`; MIR_NONE if none */
  MirTy slot_glue;   /* the unscoped type whose slot drop and copy glue it points at, or MIR_NONE */
  bool has_eq_hash;  /* the type has `Equal` and `Hashable` glue (MirModule.desc_glue) */
  uint32_t eq, hash; /* their function ids */
} MirDescPlan;

/* How a descriptor for `key` (a type under an implementation scope) is made. */
MirDescPlan mir_desc_plan(const MirModule *module, MirLayouts *layouts, MirTy key);

#endif

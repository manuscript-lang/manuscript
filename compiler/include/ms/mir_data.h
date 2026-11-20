/* The static data every backend emits the same way: type descriptors, interface vtables and global
 * variables. MIR decides what each symbol holds (name, alignment, bytes, and the addresses inside
 * it); a backend only prints that in its own text. Relocations name a data symbol, a function or a
 * symbol the runtime defines, so no backend carries layout knowledge. Port of
 * crates/ms-mir/src/statics.rs without the string literals and unit blocks, which come later. */
#ifndef MS_MIR_DATA_H
#define MS_MIR_DATA_H

#include "ms/mir.h"
#include "ms/mir_layout.h"
#include "ms/mir_pass.h"

/* The `kind` word of a descriptor (runtime/include/ms_rt/desc.h, MsKind). */
enum {
    MIR_DESC_SHARED = 5, MIR_DESC_POD = 6, MIR_DESC_LIST = 7, MIR_DESC_MAP = 8, MIR_DESC_SET = 9,
    MIR_DESC_CUSTOM = 10
};

/* The descriptor's word offsets (MsTypeDesc): size and alignment, kind, then the addresses. */
enum {
    MIR_DESC_BYTES = 64, MIR_DESC_INNER0 = 16, MIR_DESC_INNER1 = 24, MIR_DESC_DROP = 32,
    MIR_DESC_COPY = 40, MIR_DESC_EQ = 48, MIR_DESC_HASH = 56
};

/* The scope of a key whose type is plain bits whatever it holds (a forgotten value). */
#define MIR_FORGOTTEN_SCOPE ((1u << (32 - MIR_SCOPE_SHIFT)) - 1)

/* What an address points at. */
typedef enum MirRefKind { MT_DATA, MT_FUNC, MT_RUNTIME } MirRefKind;

typedef struct MirRef {
    MirRefKind kind;
    uint32_t index;       /* MT_DATA: index in `MirData.syms`; MT_FUNC: function id */
    const char *runtime;  /* MT_RUNTIME: the symbol */
} MirRef;

/* The eight bytes at `offset` of the symbol hold the address of `to`. */
typedef struct MirReloc {
    uint32_t offset;
    MirRef to;
} MirReloc;

typedef struct MirDataSym {
    const char *name;
    uint32_t size;
    uint32_t align;
    bool writable;
    const uint8_t *bytes; /* `size` bytes, NULL for all zero */
    MirReloc *relocs;
    uint32_t nrelocs;
} MirDataSym;

typedef struct MirDescKey {
    MirTy key;
    MirRef to;
} MirDescKey;

typedef struct MirData {
    MirDataSym *syms;
    uint32_t nsyms, csyms;
    uint32_t *globals;    /* symbol of each module global */
    uint32_t *vtables;    /* symbol of each module vtable */
    MirDescKey *keys;     /* every descriptor key seen, with its target */
    uint32_t nkeys, ckeys;
} MirData;

/* How a descriptor for `key` (a type under an implementation scope) is made. */
typedef struct MirDescPlan {
    const char *runtime;  /* a descriptor the runtime defines, else NULL */
    uint32_t size, align, kind;
    MirTy inner[2];       /* element, or key and value, under the scope of `key`; MIR_NONE if none */
    MirTy slot_glue;      /* the unscoped type whose slot drop and copy glue it points at, or MIR_NONE */
    bool has_eq_hash;     /* the type has `Equal` and `Hashable` glue (`MirModule.desc_glue`) */
    uint32_t eq, hash;    /* their function ids */
} MirDescPlan;

void mir_desc_plan(const MirModule *m, MirLayouts *lay, MirTy key, MirDescPlan *out);

/* The data of `m`: one symbol per global and vtable, and one per descriptor any function names
 * (and any inner descriptor those name). Run after glue, whose functions the symbols point at.
 * Everything lives in the module's arena. */
void mir_data_build(MirModule *m, const MirGlue *glue, MirData *out);

/* The target of the descriptor for `key`, which `mir_data_build` saw in a function. */
MirRef mir_data_desc(const MirData *d, MirTy key);

#endif

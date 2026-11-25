/* compiler/mir/mir_layout.h: which recursive types live behind a pointer (boxing), and the machine layout of
 * every type.
 *
 * A value is flattened into scalar leaves that live in registers; the same leaves, laid out with natural
 * alignment, are its memory representation (list elements, boxed alternatives, stack slots handed to the
 * runtime). Both queries read a finished module and never change it. The types they are asked about must
 * already be in the module's type table, and the table must not grow while a MirBoxing or MirLayouts is in
 * use. Everything a MirLayouts returns is owned by it and valid until mir_layouts_free. */
#ifndef MS_COMPILER_MIR_MIR_LAYOUT_H
#define MS_COMPILER_MIR_MIR_LAYOUT_H

#include "compiler/mir/mir.h"

/* Types are followed this deep through the fields they hold by value. A type nested deeper is reported
 * through `failed` and answered as not boxed; real programs stay far below it. */
#define MIR_LAYOUT_MAX_DEPTH 2000

/* ---- boxing ---- */

/* An alternative or an optional that contains itself by value lives behind a pointer. One MirBoxing
 * remembers the answers for a module. An answer given while a cycle is still being explored is provisional, so
 * the result of a query can depend on which queries came before it in the same MirBoxing. */
typedef struct MirBoxing {
  const MirModule *module; /* borrowed from the caller, valid until mir_boxing_free */
  MsArena arena;           /* owned: the memo tables */
  uint8_t *alts;           /* owned: per alternative, 0 unknown, 1 not boxed, 2 boxed */
  uint8_t *opts;           /* owned: per inner type of an optional, the same codes */
  uint32_t depth;
  bool failed;             /* some query went past MIR_LAYOUT_MAX_DEPTH */
} MirBoxing;

void mir_boxing_init(MirBoxing *boxing, const MirModule *module);
void mir_boxing_free(MirBoxing *boxing);

/* Whether alternative `alt` contains itself by value. */
bool mir_boxing_alt(MirBoxing *boxing, uint32_t alt);

/* Whether `inner?` contains itself by value. */
bool mir_boxing_opt(MirBoxing *boxing, MirTy inner);

/* Whether `opt<inner>` is boxed, for a caller that holds no MirBoxing (the module's types must be complete for `inner`). */
bool mir_ty_opt_boxed(const MirModule *module, MirTy inner);

/* ---- leaves and memory layout ---- */

typedef uint8_t MirLeaf;

enum {
  MIR_LEAF_I64, /* 64-bit integer or pointer */
  MIR_LEAF_F64,
  MIR_LEAF_I8,  /* booleans, presence flags */
  MIR_LEAF_N8,  /* Int8: an i64 register, one byte in memory */
  MIR_LEAF_N16,
  MIR_LEAF_N32,
  MIR_LEAF_U8,  /* UInt8: zero-extended in the register */
  MIR_LEAF_U16,
  MIR_LEAF_U32,
  MIR_LEAF_F32, /* Float32: an f64 register, four bytes in memory */
  MIR_LEAF_COUNT
};

/* Size and alignment of a leaf in memory. */
uint32_t mir_leaf_size(MirLeaf leaf);

/* A sequence of leaves is a span of bytes (each byte one MirLeaf). */
static inline MsSpan mir_leaf_span(const MirLeaf *leaves, size_t count) {
  return ms_span_of(leaves, count);
}

typedef struct MirMemLayout {
  uint32_t size;  /* rounded up to the alignment */
  uint32_t align; /* the widest leaf, 1 for none */
} MirMemLayout;

/* Natural-alignment layout of the leaves. When `offsets` is not NULL it receives each leaf's byte offset. */
MirMemLayout mir_mem_layout(MsSpan leaves, uint32_t *offsets);

typedef enum MirAltRepr {
  MIR_ALT_NONE,   /* not an alternative */
  MIR_ALT_INLINE, /* tag and payload slots in registers */
  MIR_ALT_BOXED   /* a pointer to a block with the same memory layout */
} MirAltRepr;

/* The flattened shape of a type. For an alternative, case `c` has the payload slots
 * `slots[slot_start[c] .. slot_start[c + 1]]`: for each of its payload leaves, the index into `leaves`
 * (inline; the tag is leaf 0) or into `block` (boxed). */
typedef struct MirShape {
  MsSpan leaves;
  uint8_t alt;                /* a MirAltRepr */
  const uint32_t *slot_start; /* ncases + 1 entries; NULL unless an alternative */
  const uint32_t *slots;
  MsSpan block;               /* the heap block of a boxed alternative, tag first */
} MirShape;

/* One field of one case: its type and the leaf indices (into the alternative's leaf or block list) of its
 * leaves. */
typedef struct MirAltField {
  MirTy ty;
  const uint32_t *leaves;
  uint32_t nleaves;
} MirAltField;

/* Per case, the fields of `fields[case_start[c] .. case_start[c + 1]]`. */
typedef struct MirAltFields {
  const uint32_t *case_start;
  const MirAltField *fields;
  uint32_t ncases;
} MirAltFields;

/* One capture of a closure object: its type, byte offset from the object start, and leaves. */
typedef struct MirCaptureSlot {
  MirTy ty;
  uint32_t offset;
  MsSpan leaves;
} MirCaptureSlot;

/* A closure object: the header, then each capture naturally aligned. */
typedef struct MirClosureLayout {
  const MirCaptureSlot *captures;
  uint32_t ncaptures;
  uint32_t size; /* a whole number of words */
} MirClosureLayout;

/* Where the closure's first capture starts and how many words a map or set holds. */
#define MIR_CLOSURE_CAPTURES_OFFSET 24
#define MIR_MAP_WORDS 7

/* A list or bytes value is three leaves: the element address, the length and the capacity. */
#define MIR_LIST_LEN_LEAF 1
#define MIR_LIST_CAP_LEAF 2

/* A type with more leaves than this is a failure, not a layout. */
#define MIR_LAYOUT_MAX_LEAVES (1u << 20)

typedef struct MirLayouts {
  const MirModule *module;    /* borrowed from the caller, valid until mir_layouts_free */
  MsArena arena;              /* owned: every table below */
  MirBoxing boxing;
  MirShape *shapes;           /* owned: by type */
  uint8_t *state;             /* owned: by type, 0 not computed, 1 computed */
  MirAltFields *alt_fields;   /* owned: by alternative */
  uint8_t *alt_fields_state;
  const bool **pointer_marks; /* owned: by type, NULL until asked */
  const bool **bool_marks;
  uint32_t depth;
  bool failed; /* a type was nested too deep or had too many leaves; its shape is empty */
} MirLayouts;

void mir_layouts_init(MirLayouts *layouts, const MirModule *module);
void mir_layouts_free(MirLayouts *layouts);

/* Whether alternative `alt` lives behind a pointer; whether `inner?` does. */
bool mir_layouts_alt_boxed(MirLayouts *layouts, uint32_t alt);
bool mir_layouts_opt_boxed(MirLayouts *layouts, MirTy inner);

const MirShape *mir_shape(MirLayouts *layouts, MirTy ty);

/* The register leaves of `ty`. */
MsSpan mir_leaves(MirLayouts *layouts, MirTy ty);
MirMemLayout mir_type_mem(MirLayouts *layouts, MirTy ty);
const MirAltFields *mir_alt_fields(MirLayouts *layouts, uint32_t alt);

/* The payload leaf of case `case_index` that fills slot `slot` of its alternative: operand `*operand` (a
 * field), leaf `*leaf` of it. False when the case leaves that slot unused. */
MS_NODISCARD MS_NONNULL bool mir_alt_slot_source(const MirAltFields *fields, uint32_t case_index, uint32_t slot,
                                                 uint32_t *operand, uint32_t *leaf);

/* The byte offset of field `field` of the inline record `type_id` in its memory image. */
uint32_t mir_field_offset(MirLayouts *layouts, uint32_t type_id, uint32_t field);

/* The size in bytes of one element of list type `list`. */
uint32_t mir_list_elem_size(MirLayouts *layouts, MirTy list);

/* Whether a field of this type is held as a pointer to a header block (a map or set). */
bool mir_type_field_boxed(const MirLayouts *layouts, MirTy field_ty);

/* The heap block behind a record of an indirect type: the leaves of its fields in order (as mir_type_block),
 * their byte offsets, the index of each field's first leaf, and the block size. A map or set field is one
 * pointer word to a header block of MIR_MAP_WORDS words, NULL while the collection is empty. All arrays live
 * in the layouts' arena. */
typedef struct MirRecordBlock {
  const MirTypeDef *def;
  MsSpan leaves;
  const uint32_t *offsets; /* by leaf */
  const uint32_t *starts;  /* by field */
  const bool *boxed;       /* by field */
  uint32_t size;
} MirRecordBlock;

MirRecordBlock mir_record_block(MirLayouts *layouts, uint32_t type_id);

/* Whether the runtime takes a value of `ty` as its scalar leaves: scalars, pointers, handles and the small
 * optionals of them. Anything else crosses as the address of a copy. */
bool mir_rt_direct(const MirModule *module, MirLayouts *layouts, MirTy ty);

/* Whether `ty` is a map or set. */
bool mir_ty_is_map_or_set(const MirModule *module, MirTy ty);

/* The size of the heap block of the boxed alternative `ty`; false for any other type. */
MS_NODISCARD MS_NONNULL bool mir_boxed_block_size(MirLayouts *layouts, MirTy ty, uint32_t *size);

/* The object layout of function `func` (header only when it is not a closure). */
MirClosureLayout mir_closure_layout(MirLayouts *layouts, const MirFunc *func);

/* Whether `inner?` is a nullable pointer. */
bool mir_opt_is_nullable(MirLayouts *layouts, MirTy inner);

/* Whether the optional `opt` is held as a presence flag followed by its payload leaves. Not so for a nullable
 * pointer, for a boxed payload (a pointer) or for a string, whose none is the null pointer with the static
 * tag. */
bool mir_opt_has_flag(MirLayouts *layouts, MirTy opt);

/* Whether values of `ty` have the string layout: `String`, and `String?`. */
bool mir_is_str_like(const MirLayouts *layouts, MirTy ty);

#endif

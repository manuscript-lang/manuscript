/* MIR layout: which recursive types live behind a pointer (boxing), and the machine layout of
 * every type (port of crates/ms-mir layout.rs and the `Boxing` of ir/module.rs).
 *
 * Both read a finished module and never change it. The types they are asked about must already be
 * in the module's type table, and the table must not grow while a `MirBoxing` or `MirLayouts` is
 * in use. */
#ifndef MS_MIR_LAYOUT_H
#define MS_MIR_LAYOUT_H

#include "ms/mir.h"

/* Types are followed this deep through the fields they hold by value. A type nested deeper is
 * reported through `failed` and answered as not boxed; real programs stay far below it. */
#define MIR_LAYOUT_MAX_DEPTH 2000

/* ---- boxing ---- */

/* An alternative or an optional that contains itself by value lives behind a pointer. One
 * `MirBoxing` remembers the answers for a module; as in the Rust version, an answer given while a
 * cycle is still being explored is provisional, so the result of a query can depend on which
 * queries came before it in the same `MirBoxing`. */
typedef struct MirBoxing {
    const MirModule *module; /* borrowed from the caller, valid until mir_boxing_free */
    MsArena arena;           /* owned: the memo tables and the visit lists */
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

/* One-off queries with no memory between them (`Module::opt_is_boxed`). */
bool mir_alt_is_boxed(const MirModule *module, uint32_t alt);
bool mir_opt_is_boxed(const MirModule *module, MirTy inner);

/* ---- machine layout ----
 *
 * A value is flattened into scalar leaves that live in registers; the same leaves, laid out with
 * natural alignment, are its memory representation (list elements, boxed alternatives, stack
 * slots handed to the runtime). The table of shapes is in crates/ms-mir/src/layout.rs's header.
 *
 * Everything a MirLayouts returns is owned by it and valid until mir_layouts_free. */

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
/* The lower-case name used in dumps (`i64`, `n8`, ...). */
const char *mir_leaf_name(MirLeaf leaf);

typedef struct MirLeafSpan {
    const MirLeaf *ptr; /* borrowed from the MirLayouts that returned it */
    uint32_t len;
} MirLeafSpan;

typedef struct MirMemLayout {
    uint32_t size;  /* rounded up to the alignment */
    uint32_t align; /* the widest leaf, 1 for none */
} MirMemLayout;

/* Natural-alignment layout of `count` leaves. When `offsets` is not null it receives each leaf's
 * byte offset. */
MirMemLayout mir_mem_layout(const MirLeaf *leaves, uint32_t count, uint32_t *offsets);

typedef enum MirAltRepr {
    MIR_ALT_NONE,   /* not an alternative */
    MIR_ALT_INLINE, /* tag and payload slots in registers */
    MIR_ALT_BOXED   /* a pointer to a block with the same memory layout */
} MirAltRepr;

/* The flattened shape of a type. For an alternative, case `c` has the payload slots
 * `slots[slot_start[c] .. slot_start[c + 1]]`: for each of its payload leaves, the index into
 * `leaves` (inline; the tag is leaf 0) or into `block` (boxed). */
typedef struct MirShape {
    MirLeafSpan leaves;
    uint8_t alt; /* MirAltRepr */
    const uint32_t *slot_start; /* ncases + 1 entries; null unless an alternative */
    const uint32_t *slots;
    MirLeafSpan block; /* the heap block of a boxed alternative, tag first */
} MirShape;

/* One field of one case: its type and the leaf indices (into the alternative's leaf or block
 * list) of its leaves. */
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
    MirLeafSpan leaves;
} MirCaptureSlot;

/* A closure object: the header, then each capture naturally aligned. */
typedef struct MirClosureLayout {
    const MirCaptureSlot *captures;
    uint32_t ncaptures;
    uint32_t size; /* a whole number of words */
} MirClosureLayout;

/* Where the closure's first capture starts (`ms_rt_abi::CLOSURE_CAPTURES_OFFSET`) and how many
 * words a map or set holds (`ms_rt_abi::MAP_SIZE / 8`). */
#define MIR_CLOSURE_CAPTURES_OFFSET 24
/* Task stacks live in regions of this size, aligned to it; the recursion limit is the word this many
 * bytes before the region's end (`ms_rt_abi::symbols::STACK_REGION`, `STACK_LIMIT_CELL`). */
#define MIR_STACK_REGION ((int64_t)256 << 20)
#define MIR_STACK_LIMIT_CELL 8
/* The word this many bytes before the region's end holds the task header's address; the header's
 * cancel flag is the byte at `MIR_HDR_CANCEL` (`ISOLATE_HDR_CANCEL`). */
#define MIR_STACK_HDR_CELL 16
#define MIR_HDR_CANCEL 8

/* The tag bits of a string's second word (src/runtime/include/ms_rt/string.h) and the longest inline string. */
#define MIR_STR_STATIC ((uint64_t)1 << 63)
#define MIR_STR_INLINE ((uint64_t)1 << 62)
#define MIR_STR_ASCII ((uint64_t)1 << 61)
#define MIR_STR_INLINE_SHIFT 56
#define MIR_STR_INLINE_MAX 15

/* A list or bytes value is three leaves: the element address, the length and the capacity. */
#define MIR_LIST_LEN_LEAF 1
#define MIR_LIST_CAP_LEAF 2
#define MIR_MAP_WORDS 7
/* A type with more leaves than this is a failure, not a layout. */
#define MIR_LAYOUT_MAX_LEAVES (1u << 20)

typedef struct MirLayouts {
    const MirModule *module; /* borrowed from the caller, valid until mir_layouts_free */
    MsArena arena;           /* owned: every table below */
    MirBoxing boxing;
    MirShape *shapes;        /* owned: by type */
    uint8_t *state;          /* owned: by type, 0 not computed, 1 computed */
    MirAltFields *alt_fields; /* owned: by alternative */
    uint8_t *alt_fields_state;
    const bool **pointer_marks; /* owned: by type, null until asked */
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
/* The register leaves of `ty`, and how many. */
MirLeafSpan mir_leaves(MirLayouts *layouts, MirTy ty);
MirMemLayout mir_type_mem(MirLayouts *layouts, MirTy ty);
const MirAltFields *mir_alt_fields(MirLayouts *layouts, uint32_t alt);
/* The payload leaf of case `case_index` that fills slot `slot` of its alternative: operand `*operand`
 * (a field), leaf `*leaf` of it. False when the case leaves that slot unused. */
bool mir_alt_slot_source(const MirAltFields *fields, uint32_t case_index, uint32_t slot,
                         uint32_t *operand, uint32_t *leaf);

/* The leaves of the heap block behind indirect type `type_id`: its fields' leaves in order,
 * except that a map or set field is one pointer to a header block that exists only while the
 * collection is not the all-zero empty value. */
MirLeafSpan mir_type_block(MirLayouts *layouts, uint32_t type_id);
/* The byte offset of field `field` of the inline record `type_id` in its memory image. */
/* The size in bytes of one element of list type `list`. */
uint32_t mir_list_elem_size(MirLayouts *layouts, MirTy list);
uint32_t mir_field_offset(MirLayouts *layouts, uint32_t type_id, uint32_t field);
bool mir_type_field_boxed(const MirLayouts *layouts, MirTy field_ty);
/* The heap block behind a record of an indirect type: `leaves` of its fields in order (as
 * mir_type_block), their byte `offsets`, the index of each field's first leaf in `starts`, and the
 * block `size`. A map or set field is one pointer word to a header block of MIR_MAP_WORDS words,
 * null while the collection is empty (`boxed`). Free with mir_record_block_free. */
typedef struct MirRecordBlock {
    const MirTypeDef *def;
    MirLeafSpan leaves;
    uint32_t *offsets;
    uint32_t *starts;
    bool *boxed;
    uint32_t size;
} MirRecordBlock;

/* Fills `out` for the indirect record type declaration `type_id`; false when out of memory. */
bool mir_record_block(MirLayouts *layouts, uint32_t type_id, MirRecordBlock *out);
void mir_record_block_free(MirRecordBlock *block);
/* Whether `ty` is a map or set. */
bool mir_ty_is_map_or_set(const MirModule *module, MirTy ty);

/* The size of the heap block of the boxed alternative `ty`; false for any other type. */
bool mir_boxed_block_size(MirLayouts *layouts, MirTy ty, uint32_t *size);
/* The object layout of function `f` (header only when it is not a closure). */
MirClosureLayout mir_closure_layout(MirLayouts *layouts, const MirFunc *f);

/* One flag per leaf of `ty`: a pointer (nullable included), or a boolean. See layout.rs. */
const bool *mir_pointer_leaves(MirLayouts *layouts, MirTy ty);
const bool *mir_bool_leaves(MirLayouts *layouts, MirTy ty);

/* Whether `inner?` is a nullable pointer. */
bool mir_opt_is_nullable(MirLayouts *layouts, MirTy inner);
/* Whether the optional `opt` is held as a presence flag followed by its payload leaves. Not so for
 * a nullable pointer, for a boxed payload (a pointer) or for a string, whose none is the null
 * pointer with the static tag. */
bool mir_opt_has_flag(MirLayouts *layouts, MirTy opt);
/* Whether values of `ty` have the string layout: `String`, and `String?`. */
bool mir_is_str_like(const MirLayouts *layouts, MirTy ty);

/* Whether the runtime takes a value of `ty` as its scalar leaves (the C ABI of the runtime): scalars,
 * pointers, handles and the small optionals of them. Anything else crosses as the address of a copy. */
bool mir_rt_direct(const MirModule *m, MirLayouts *layouts, MirTy ty);

#endif

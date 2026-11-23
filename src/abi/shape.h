/* abi/shape.h: the shape table of a type, which lets one runtime walker read or build a value of any type.
 *
 * The compiler emits one table per distinct type `T` that reaches a generic native (`msstd_test_repr[T]`, the
 * text form of an interpolation, `msstd_json_stringify[T]`, `msstd_json_parse[T]`) and passes it as a hidden
 * first argument. The table is a flat byte image with no pointers, so it is plain read-only data: shapes and
 * members are arrays indexed by number and names are offsets into a string area. What cannot be data (a
 * type's own `to_string`, a record field's default, a type descriptor for erased maps) is reached through
 * the optional hook arrays of MsShapeTable, indexed by shape or member number.
 *
 * Where a value sits decides how it is read, and the table says so for each shape:
 *
 *   - A value in a slot is read at its `size` bytes: integers and floats at their natural width, Bool as one
 *     byte, String as an MsString (16 bytes), Bytes and List as an MsList, Map and Set as an MsMap.
 *   - A RECORD slot holds its fields inline at their `offset`s. An ALTERNATIVE slot holds an i64 tag at
 *     `extra`, then the payload fields of the active case at their `offset`s, which share space between
 * cases.
 *   - A shape with MS_SHAPE_BOXED holds one pointer to a heap block with that same layout (recursive types).
 *   - OPTIONAL: with MS_SHAPE_NULLABLE the value is none when the first eight bytes are zero and the payload
 *     is the slot itself (with MS_SHAPE_HEAP_PAYLOAD the slot is a pointer, null for none, to a heap block that
 *     holds the payload: an optional of a recursive type); otherwise a presence byte sits at offset 0 and the payload at `extra`.
 *   - Result is an ALTERNATIVE (`ok` is case 0, `error` case 1), named Result.
 *
 * Every integer is in the machine's byte order. A table passes MsShapeImage's magic and the static asserts
 * below; a table that does not describe the value it is read with is a compiler bug. */
#ifndef MS_ABI_SHAPE_H
#define MS_ABI_SHAPE_H

#include <stddef.h>
#include <stdint.h>

#include "base/desc.h"
#include "base/string.h"

#define MS_SHAPE_MAGIC UINT32_C(0x4853534d) /* "MSSH" */
#define MS_SHAPE_NONE UINT32_MAX            /* no name, no shape, no hook */

typedef enum MsShapeKind {
  MS_SHAPE_VOID = 0,         /* no bytes */
  MS_SHAPE_BOOL = 1,         /* one byte, 0 or 1 */
  MS_SHAPE_INT = 2,          /* signed, `size` 1, 2, 4 or 8 */
  MS_SHAPE_UINT = 3,         /* unsigned, `size` 1, 2, 4 or 8 */
  MS_SHAPE_FLOAT = 4,        /* `size` 4 (Float32) or 8 (Float) */
  MS_SHAPE_STRING = 5,       /* an MsString */
  MS_SHAPE_BYTES = 6,        /* an MsBytes */
  MS_SHAPE_LIST = 7,         /* an MsList of `elem` */
  MS_SHAPE_MAP = 8,          /* an MsMap from `elem` to `value` */
  MS_SHAPE_SET = 9,          /* an MsMap of `elem` */
  MS_SHAPE_OPTIONAL = 10,    /* `elem` or none */
  MS_SHAPE_RECORD = 11,      /* `count` fields from member `first` */
  MS_SHAPE_ALTERNATIVE = 12, /* `count` cases from member `first` */
  MS_SHAPE_BIGINT = 13,      /* a BigInt handle: text from the hook's to_text, JSON a number */
  MS_SHAPE_DECIMAL = 14,     /* a Decimal: the same */
  MS_SHAPE_OPAQUE = 15,      /* shown as its type name only */
  MS_SHAPE_FUNCTION = 16,    /* shown as "[function]" */
  MS_SHAPE_OBJECT = 17,      /* a handle, shown as "[object]" */
  MS_SHAPE_COUNT
} MsShapeKind;

enum {
  MS_SHAPE_BOXED = 1u << 0,     /* the slot holds a pointer to a block with this shape's layout */
  MS_SHAPE_NULLABLE = 1u << 1,  /* OPTIONAL: none is eight zero bytes and the payload is the slot itself */
  MS_SHAPE_TEXT_FORM = 1u << 2, /* the shape's hooks supply the text form (its own `to_string`) */
  MS_SHAPE_JSON_FORM =
      1u << 3, /* the shape's hooks supply its JSON form (a JsonEncode, Url, Timestamp, ...) */
  MS_SHAPE_NAME_ONLY = 1u << 6, /* RECORD and ALTERNATIVE: an `opaque` type, whose text is its type name only */
  MS_SHAPE_HEAP_PAYLOAD = 1u << 5, /* OPTIONAL with NULLABLE: the slot points to a heap block holding the payload */
  MS_SHAPE_JSON_TREE = 1u << 4 /* ALTERNATIVE: the untyped JSON value (null, bool, number, string, array, object cases),
                                  written as its own document */
};

typedef struct MsShapeImage {
  uint32_t magic;
  uint32_t shapes_at; /* byte offsets from the start of the image */
  uint32_t shape_count;
  uint32_t members_at;
  uint32_t member_count;
  uint32_t strings_at;
  uint32_t strings_size;
  uint32_t root; /* the shape of `T` */
} MsShapeImage;

typedef struct MsShape {
  uint8_t kind;   /* MsShapeKind */
  uint8_t flags;  /* MS_SHAPE_* */
  uint16_t align; /* of the slot */
  uint32_t size;  /* of the slot (BOXED: of the pointer) */
  uint32_t name;  /* the type's name without type arguments, as a string offset, or MS_SHAPE_NONE */
  uint32_t first; /* RECORD and ALTERNATIVE: the first member */
  uint32_t count; /* RECORD and ALTERNATIVE: the number of members */
  uint32_t elem;  /* LIST, SET, MAP (key), OPTIONAL: the element shape */
  uint32_t value; /* MAP: the value shape; BOXED RECORD and ALTERNATIVE: the size of the block */
  uint32_t extra; /* ALTERNATIVE: the tag offset; OPTIONAL: the payload offset when it has a presence byte */
} MsShape;

/* A record field, an alternative case, or a field of a case's payload. */
typedef struct MsShapeMember {
  uint32_t name;  /* string offset */
  uint32_t shape; /* a field's shape; MS_SHAPE_NONE on a case */
  uint32_t
      offset;   /* a field's offset in the value (a case's payload fields are relative to the alternative) */
  uint32_t tag; /* a case's tag value */
  uint32_t first; /* a case: its first payload field, in this array */
  uint32_t count; /* a case: the number of payload fields (zero for a bare case) */
  uint32_t flags; /* MS_SHAPE_MEMBER_* */
  uint32_t reserved;
} MsShapeMember;

enum {
  MS_SHAPE_MEMBER_DEFAULT = 1u << 0, /* a field with a default; MsShapeTable.defaults[member] builds it */
  MS_SHAPE_MEMBER_LABELED = 1u << 1  /* a case's payload field written with a label */
};

_Static_assert(sizeof(MsShapeImage) == 32, "shape image header is ABI");
_Static_assert(sizeof(MsShape) == 32 && offsetof(MsShape, extra) == 28, "shape layout is ABI");
_Static_assert(sizeof(MsShapeMember) == 32 && offsetof(MsShapeMember, flags) == 24, "member layout is ABI");

/* The hooks of one shape, indexed by shape number; all optional. */
typedef struct MsShapeHook {
  /* The type descriptor of a slot of this shape; LIST, MAP, SET and every shape built by a parse need it. */
  const MsTypeDesc *desc;
  /* The shape's own text (`fn T.to_string() String`), used when MS_SHAPE_TEXT_FORM is set. `value` is the slot that
   * holds the value (for a boxed shape, the pointer to its block), and the text is moved into `out`. */
  void (*to_text)(const void *value, MsString *out);
  /* A shape with its own JSON form, when MS_SHAPE_JSON_FORM is set: writes the value to the JSON writer (the
   * msstd_json_w_* natives) and returns 0, or nonzero when the value has no JSON form and nothing was
   * written. */
  uint8_t (*json_encode)(const void *value, void *writer);
  /* The reverse for a parse: reads the node `id` of the document and writes the slot `out`; returns 0, or the
   * status of the failure. */
  uint8_t (*json_decode)(const void *doc, uint32_t id, void *out);
} MsShapeHook;

/* What a generic native receives: the image, and the hook arrays when the type needs any. */
typedef struct MsShapeTable {
  const MsShapeImage *image;
  const MsShapeHook *hooks; /* per shape, or NULL */
  /* per member, or NULL; builds a field's default value in place at `out`; `record` is the value being built,
   * whose earlier fields are set (a default may read them) */
  void (*const *defaults)(uint8_t *out, const uint8_t *record);
} MsShapeTable;

static inline const MsShape *ms_shape_at(const MsShapeTable *table, uint32_t index) {
  return (const MsShape *)(const void *)((const uint8_t *)table->image + table->image->shapes_at) + index;
}

static inline const MsShapeMember *ms_shape_member(const MsShapeTable *table, uint32_t index) {
  return (const MsShapeMember *)(const void *)((const uint8_t *)table->image + table->image->members_at) +
         index;
}

/* The NUL-terminated name at string offset `offset`; "" for MS_SHAPE_NONE. */
static inline const char *ms_shape_text(const MsShapeTable *table, uint32_t offset) {
  return offset == MS_SHAPE_NONE ? "" : (const char *)table->image + table->image->strings_at + offset;
}

static inline const MsShapeHook *ms_shape_hook(const MsShapeTable *table, uint32_t index) {
  return table->hooks == NULL ? NULL : &table->hooks[index];
}

/* The block a BOXED shape's slot points to, or the slot itself. */
static inline const uint8_t *ms_shape_resolve(const MsShape *shape, const uint8_t *slot) {
  return (shape->flags & MS_SHAPE_BOXED) != 0 ? *(const uint8_t *const *)(const void *)slot : slot;
}

/* The payload of an OPTIONAL slot, or NULL when it is none. */
static inline const uint8_t *ms_shape_some(const MsShape *shape, const uint8_t *slot) {
  if ((shape->flags & MS_SHAPE_HEAP_PAYLOAD) != 0) {
    return *(const uint8_t *const *)(const void *)slot;
  }
  if ((shape->flags & MS_SHAPE_NULLABLE) != 0) {
    return *(const uint64_t *)(const void *)slot != 0 ? slot : NULL;
  }
  return *slot != 0 ? slot + (int32_t)shape->extra : NULL; /* signed: inside an alternative's image the payload can lie before the flag */
}

/* The case of an ALTERNATIVE value at `base` that its tag selects. */
static inline const MsShapeMember *ms_shape_active_case(const MsShapeTable *table, const MsShape *shape,
                                                        const uint8_t *base) {
  const int64_t tag = *(const int64_t *)(const void *)(base + shape->extra);
  for (uint32_t at = 0; at < shape->count; at++) {
    const MsShapeMember *candidate = ms_shape_member(table, shape->first + at);
    if ((int64_t)candidate->tag == tag) {
      return candidate;
    }
  }
  return ms_shape_member(table, shape->first);
}

#endif

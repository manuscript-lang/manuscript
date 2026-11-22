/* ms_rt/json.h: the @std/data/json natives (src/runtime/std/json_*.c). Fallible functions return a status (0
 * ok, 1 InvalidInput, 3 LimitExceeded, 4 InvalidData) and write their result through `out` only on success. A
 * document and a writer are handle objects the program owns; node ids are only valid for the document that
 * issued them. Symbols are listed in src/runtime/symbols/json.txt.
 *
 * The untyped `JsonValue` has a layout the compiler chooses, so it passes two thunks with the value's
 * descriptor: a constructor `ctor(case, payload, out)` that moves a payload (a Bool byte, a String, a list or
 * a String-keyed map of the alternative) into a new value of the case (null 0, bool 1, number 2, string 3,
 * array 4, object 5), and a view `view(value, sink, walk)` that writes a value's case itself. */
#ifndef MS_RUNTIME_STD_JSON_H
#define MS_RUNTIME_STD_JSON_H

#include "abi/status.h"
#include "base/desc.h"
#include "base/list.h"
#include "base/map.h"
#include "base/string.h"

/* ms: domain JSON */

typedef struct JsonWalk JsonWalk;
typedef int64_t (*JsonCtorFn)(int64_t kind, uint8_t *payload, uint8_t *out);
typedef void (*JsonViewFn)(const uint8_t *value, uint8_t *sink, uint8_t *walk);

/* Parses `text` into a document: on success *out is a new handle object the caller owns and *root the root
 * node id. A syntax error is InvalidData and, when `err` is not null, sets it to `line L, column C:
 * <reason>`. */
/* ms-sig: msstd_json_parse(text: *const StrVal, has_max_bytes: HasRaw, max_bytes: i64, has_max_depth: HasRaw,
 * max_depth: i64, has_max_values: HasRaw, max_values: i64, out: *mut *mut ObjCell<Doc>, root: *mut u32, err:
 * ErrSlot) -> u8 @leaf */
uint8_t msstd_json_parse(const MsString *text, uint8_t has_max_bytes, int64_t max_bytes,
                         uint8_t has_max_depth, int64_t max_depth, uint8_t has_max_values, int64_t max_values,
                         void **out, uint32_t *root, MsString *err);

/* Parses `text` straight into a value of the recursive alternative described by `desc`, built by `ctor` (see
 * the notes above), written to `out` on success. */
/* ms-sig: msstd_json_parse_tree(text: *const StrVal, has_max_bytes: HasRaw, max_bytes: i64, has_max_depth:
 * HasRaw, max_depth: i64, has_max_values: HasRaw, max_values: i64, desc: ValueDesc, ctor: TreeCtor, out: *mut
 * u8, err: ErrSlot) -> u8 @domain=JSON @leaf */
uint8_t msstd_json_parse_tree(const MsString *text, uint8_t has_max_bytes, int64_t max_bytes,
                              uint8_t has_max_depth, int64_t max_depth, uint8_t has_max_values,
                              int64_t max_values, const MsTypeDesc *desc, JsonCtorFn ctor, uint8_t *out,
                              MsString *err);

/* Reading a document: a node's kind, a Bool's value, a string or number's text and an object's keys (views
 * into the document), the child count of an array or object, and the node ids of children. `i` is below the
 * count. */
/* ms-sig: msstd_json_kind(handle d: *const ObjCell<Doc>, id: u32) -> u8 @leaf */
uint8_t msstd_json_kind(const void *d, uint32_t id);
/* ms-sig: msstd_json_bool(handle d: *const ObjCell<Doc>, id: u32) -> u8 @leaf */
uint8_t msstd_json_bool(const void *d, uint32_t id);
/* ms-sig: msstd_json_text(handle d: *const ObjCell<Doc>, id: u32, out: *mut StrVal) @leaf */
void msstd_json_text(const void *d, uint32_t id, MsString *out);

/* The cold path of a typed decode: records why node `id` was rejected (code 0 the value does not fit type
 * `text`, 1 expected kind `text`, 2 missing field `text`, 3 unknown field, 4 unknown variant), and reads the
 * message back for the failed decode of the document under `root`. */
/* ms-sig: msstd_json_mismatch(handle d: *const ObjCell<Doc>, id: u32, code: i64, text: *const StrVal) @leaf
 */
void msstd_json_mismatch(const void *d, uint32_t id, int64_t code, const MsString *text);
/* ms-sig: msstd_json_mismatch_text(handle d: *const ObjCell<Doc>, root: u32, out: *mut StrVal) @leaf */
void msstd_json_mismatch_text(const void *d, uint32_t root, MsString *out);
/* ms-sig: msstd_json_len(handle d: *const ObjCell<Doc>, id: u32) -> i64 @leaf */
int64_t msstd_json_len(const void *d, uint32_t id);
/* ms-sig: msstd_json_item(handle d: *const ObjCell<Doc>, id: u32, i: i64) -> u32 @leaf */
uint32_t msstd_json_item(const void *d, uint32_t id, int64_t i);
/* ms-sig: msstd_json_key(handle d: *const ObjCell<Doc>, id: u32, i: i64, out: *mut StrVal) @leaf */
void msstd_json_key(const void *d, uint32_t id, int64_t i, MsString *out);

/* Fields: the index of member `key` of an object (-1 when absent), whether it has a member not in `names`,
 * and the index of the variant a string or single-key object names in `names`; `payload` is the payload node
 * (-1 for a bare name) and is written only for a string or single-key object. */
/* ms-sig: msstd_json_find(handle d: *const ObjCell<Doc>, id: u32, key: *const StrVal) -> i64 @leaf */
int64_t msstd_json_find(const void *d, uint32_t id, const MsString *key);
/* ms-sig: msstd_json_has_unknown(handle d: *const ObjCell<Doc>, id: u32, names: *const VecVal) -> u8 @leaf */
uint8_t msstd_json_has_unknown(const void *d, uint32_t id, const MsList *names);
/* ms-sig: msstd_json_variant(handle d: *const ObjCell<Doc>, id: u32, names: *const VecVal, payload: *mut i64)
 * -> i64 @leaf */
int64_t msstd_json_variant(const void *d, uint32_t id, const MsList *names, int64_t *payload);

/* Scalars: number text as an Int (also within lo..=hi), a UInt64 as its bit pattern, a Float32 as the double
 * holding it, a Float. A text that is not an in-range number is InvalidInput. */
/* ms-sig: msstd_json_dec_int(text: *const StrVal, out: *mut i64) -> u8 @leaf */
uint8_t msstd_json_dec_int(const MsString *text, int64_t *out);
/* ms-sig: msstd_json_dec_int_in(text: *const StrVal, lo: i64, hi: i64, out: *mut i64) -> u8 @leaf */
uint8_t msstd_json_dec_int_in(const MsString *text, int64_t lo, int64_t hi, int64_t *out);
/* ms-sig: msstd_json_dec_uint(text: *const StrVal, out: *mut i64) -> u8 @leaf */
uint8_t msstd_json_dec_uint(const MsString *text, int64_t *out);
/* ms-sig: msstd_json_dec_float32(text: *const StrVal, out: *mut f64) -> u8 @leaf */
uint8_t msstd_json_dec_float32(const MsString *text, double *out);
/* ms-sig: msstd_json_dec_float(text: *const StrVal, out: *mut f64) -> u8 @leaf */
uint8_t msstd_json_dec_float(const MsString *text, double *out);

/* The writer: typed encoders call it in document order. A budget (`has_*`, value) that is negative makes
 * `finish` answer InvalidInput; the first failure (the byte budget, a number that is not JSON, nesting past
 * the ceiling) is kept and every later call does nothing. `w_tree` walks a value of the untyped alternative
 * through `view`, which calls back into the writer's scalar natives and `tree_array` and `tree_object` for
 * containers. */
/* ms-sig: msstd_json_writer_new(has_max_bytes: HasRaw, max_bytes: i64, has_indent: HasRaw, indent: i64) ->
 * *mut ObjCell<Writer> @handle @leaf */
void *msstd_json_writer_new(uint8_t has_max_bytes, int64_t max_bytes, uint8_t has_indent, int64_t indent);
/* ms-sig: msstd_json_w_item(handle w: *mut ObjCell<Writer>) @leaf */
void msstd_json_w_item(void *w);
/* ms-sig: msstd_json_w_key(handle w: *mut ObjCell<Writer>, key: *const StrVal) @leaf */
void msstd_json_w_key(void *w, const MsString *key);
/* ms-sig: msstd_json_w_key_quoted(handle w: *mut ObjCell<Writer>, quoted_name: *const StrVal) @leaf */
void msstd_json_w_key_quoted(void *w, const MsString *quoted_name);
/* ms-sig: msstd_json_w_undo(handle w: *mut ObjCell<Writer>) @leaf */
void msstd_json_w_undo(void *w);
/* ms-sig: msstd_json_w_begin_array(handle w: *mut ObjCell<Writer>) @leaf */
void msstd_json_w_begin_array(void *w);
/* ms-sig: msstd_json_w_end_array(handle w: *mut ObjCell<Writer>) @leaf */
void msstd_json_w_end_array(void *w);
/* ms-sig: msstd_json_w_begin_object(handle w: *mut ObjCell<Writer>) @leaf */
void msstd_json_w_begin_object(void *w);
/* ms-sig: msstd_json_w_end_object(handle w: *mut ObjCell<Writer>) @leaf */
void msstd_json_w_end_object(void *w);
/* ms-sig: msstd_json_w_no_form(handle w: *mut ObjCell<Writer>) @leaf */
void msstd_json_w_no_form(void *w);
/* ms-sig: msstd_json_w_lost(handle w: *const ObjCell<Writer>) -> u8 @leaf */
uint8_t msstd_json_w_lost(const void *w);
/* ms-sig: msstd_json_w_null(handle w: *mut ObjCell<Writer>) @leaf */
void msstd_json_w_null(void *w);
/* ms-sig: msstd_json_w_bool(handle w: *mut ObjCell<Writer>, v: u8) @leaf */
void msstd_json_w_bool(void *w, uint8_t value);
/* ms-sig: msstd_json_w_int(handle w: *mut ObjCell<Writer>, v: i64) @leaf */
void msstd_json_w_int(void *w, int64_t value);
/* ms-sig: msstd_json_w_uint(handle w: *mut ObjCell<Writer>, v: i64) @leaf */
void msstd_json_w_uint(void *w, int64_t value);
/* ms-sig: msstd_json_w_float32(handle w: *mut ObjCell<Writer>, v: f64) @leaf */
void msstd_json_w_float32(void *w, double value);
/* ms-sig: msstd_json_w_float(handle w: *mut ObjCell<Writer>, v: f64) @leaf */
void msstd_json_w_float(void *w, double value);
/* ms-sig: msstd_json_w_number(handle w: *mut ObjCell<Writer>, text: *const StrVal) @leaf */
void msstd_json_w_number(void *w, const MsString *text);
/* ms-sig: msstd_json_w_string(handle w: *mut ObjCell<Writer>, text: *const StrVal) @leaf */
void msstd_json_w_string(void *w, const MsString *text);
/* ms-sig: msstd_json_w_tree(handle w: *mut ObjCell<Writer>, desc: *const TypeDesc, view: unsafe extern
 * "C-unwind" fn(*const u8, *mut u8, *mut u8), root: *const u8) @leaf */
void msstd_json_w_tree(void *w, const MsTypeDesc *desc, JsonViewFn view, const uint8_t *root);
/* ms-sig: msstd_json_tree_array(walk: *mut Walk<Writer>, list: *const VecVal) @leaf */
void msstd_json_tree_array(JsonWalk *walk, const MsList *list);
/* ms-sig: msstd_json_tree_object(walk: *mut Walk<Writer>, map: *const MapVal) @leaf */
void msstd_json_tree_object(JsonWalk *walk, const MsMap *map);
/* ms-sig: msstd_json_w_finish(handle w: *mut ObjCell<Writer>, out: *mut StrVal) -> u8 @leaf */
uint8_t msstd_json_w_finish(void *w, MsString *out);

#endif

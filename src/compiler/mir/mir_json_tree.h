/* compiler/mir/mir_json_tree.h: the constructor thunk of an untyped JSON tree (mir_json_tree.c). */
#ifndef MS_COMPILER_MIR_MIR_JSON_TREE_H
#define MS_COMPILER_MIR_MIR_JSON_TREE_H

#include "compiler/mir/mir.h"

/* Whether `ty` is the standard alternative `JsonValue`, laid out as the thunk expects: the cases Null, BoolValue,
 * NumberValue, StringValue, ArrayValue and ObjectValue in that order, the last five with one field each. */
bool mir_json_tree_shape(const MirModule *module, MirTy ty);

/* `fn(kind: int, payload: ptr, out: ptr) -> int` for `msstd_json_parse_tree`: moves the payload the runtime
 * built (a Bool byte, a String, a list or a map) into a value of case `kind` of the alternative, written to
 * `out`. MIR_NONE when `ty` is not that alternative or the build fails. */
uint32_t mir_json_tree_ctor(MirModule *module, MirTy ty);

#endif

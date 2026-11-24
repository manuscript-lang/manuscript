/* compiler/lower/lower_native_roles.c: the roles of runtime functions the optimiser rewrites in MIR: string and bytes
 * fast paths (`opt_strfast`, `opt_bytesfast`) and map and set probes (`opt_probe`). */
#include "compiler/lower/lower_fn.h"
#include "compiler/natives/native_sigs.h"

/* The role of a runtime string function the optimiser answers inline for the common case (`opt_strfast`). */
static MirRole string_role(MsSpan name) {
  static const struct {
    const char *name;
    MirRole role;
  } table[] = {{"msrt_bytes_append", MR_BYTES_APPEND},
               {"msrt_bytes_concat", MR_BYTES_CONCAT},
               {"msrt_list_sorted", MR_LIST_SORTED},
               {"msrt_bytes_read_word", MR_BYTES_READ_WORD},
               {"msrt_bytes_index_of_byte", MR_BYTES_INDEX_OF_BYTE},
               {"msrt_string_parse_int", MR_STRING_PARSE_INT},
               {"msrt_string_contains", MR_STRING_CONTAINS},
               {"msrt_string_scalar_step", MR_STRING_SCALAR_STEP},
               {"msrt_string_eq", MR_STRING_EQ},
               {"msrt_string_compare", MR_STRING_COMPARE},
               {"msrt_string_starts_with", MR_STRING_STARTS_WITH},
               {"msrt_string_ends_with", MR_STRING_ENDS_WITH},
               {"msrt_string_slice", MR_STRING_SLICE},
               {"msrt_string_scalar_at", MR_STRING_SCALAR_AT}};
  for (size_t at = 0; at < sizeof table / sizeof table[0]; at++) {
    if (ms_span_is_text(name, table[at].name)) {
      return table[at].role;
    }
  }
  return MR_NONE;
}

/* The probe role of a lookup in a map or set whose slots the optimiser can read (`opt_probe`): an `Int`
 * key and, for a map, an eight-byte `Int` or `Float` value. The runtime function says what is asked, the first
 * operand's type which shape the map has. */
static MirRole probe_role(const MirModule *module, MsSpan name, MirTy first) {
  const bool set = ms_span_is_text(name, "msrt_set_contains");
  const bool map = ms_span_is_text(name, "msrt_map_contains") || ms_span_is_text(name, "msrt_map_get") ||
                   ms_span_is_text(name, "msrt_map_get_ptr") ||
                   ms_span_is_text(name, "msrt_map_get_or");
  const MirTyData *data = mir_ty_data(module, first);
  if ((!set && !map) || data->kind != MK_OBJ || data->obj_class != MIR_OBJ_COLLECTION || data->nargs < (set ? 1u : 2u)) {
    return MR_NONE;
  }
  if (set) {
    if (data->nargs != 1) {
      return MR_NONE;
    }
    return data->args[0] == MIR_INT ? MR_SET_PROBE_INT : data->args[0] == MIR_STR ? MR_SET_PROBE_STR : MR_NONE;
  }
  const MirTy value = data->args[1];
  if (data->nargs != 2 || (value != MIR_INT && value != MIR_FLOAT)) {
    return MR_NONE;
  }
  return data->args[0] == MIR_INT ? MR_MAP_PROBE_INT : data->args[0] == MIR_STR ? MR_MAP_PROBE_STR : MR_NONE;
}

/* The role of runtime function `name` whose first operand has type `first`. */
MirRole fn_native_role(const MirModule *module, MsSpan name, MirTy first) {
  const MirRole probe = probe_role(module, name, first);
  return probe != MR_NONE ? probe : string_role(name);
}

/* The family of borrowing twins the signature declares (`@twin=`). */
MirTwin fn_native_twin(const struct MsNativeSig *sig) {
  return sig != NULL && sig->twin != NULL && ms_span_is_text(ms_span_of_text(sig->twin), "split_view") ? MTW_SPLIT_VIEW : MTW_NONE;
}

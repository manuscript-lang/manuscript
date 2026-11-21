/* compiler/mir/mir_print_ty.c: the text of types, quoted strings, floats, roles and conditions. */
#include "compiler/mir/mir_print.h"

#include "base/fmt.h"

static void put_name(const MirModule *module, MsStrBuild *out, MsName name) {
  ms_strbuild_append(out, ms_names_span(&module->names, name));
}

static void put_text(MsStrBuild *out, const char *text) {
  ms_strbuild_append_text(out, text);
}

static const char *scalar_name(MirTyKind kind) {
  switch (kind) {
  case MK_VOID: return "void";
  case MK_BOOL: return "bool";
  case MK_INT: return "int";
  case MK_FLOAT: return "float";
  case MK_INT8: return "int8";
  case MK_INT16: return "int16";
  case MK_INT32: return "int32";
  case MK_FLOAT32: return "float32";
  case MK_UINT8: return "uint8";
  case MK_UINT16: return "uint16";
  case MK_UINT32: return "uint32";
  case MK_UINT64: return "uint64";
  case MK_STR: return "str";
  case MK_BYTES: return "bytes";
  case MK_PTR: return "ptr";
  default: return NULL;
  }
}

static void print_obj(const MirModule *module, const MirTyData *data, MsStrBuild *out) {
  if (data->nargs == 0) {
    put_text(out, "obj ");
    put_name(module, out, data->name);
    return;
  }
  put_name(module, out, data->name);
  ms_strbuild_append_byte(out, '<');
  for (uint32_t index = 0; index < data->nargs; index++) {
    put_text(out, index > 0 ? ", " : "");
    mir_print_ty(module, data->args[index], out);
  }
  ms_strbuild_append_byte(out, '>');
}

static void print_fn(const MirModule *module, const MirTyData *data, MsStrBuild *out) {
  put_text(out, "fn(");
  for (uint32_t index = 0; index < data->nargs; index++) {
    put_text(out, index > 0 ? ", " : "");
    put_text(out, mir_owns(data->owned, index) ? "move " : "");
    mir_print_ty(module, data->args[index], out);
  }
  put_text(out, ") -> ");
  mir_print_ty(module, data->elem, out);
}

static void print_unscoped(const MirModule *module, MirTy type, MsStrBuild *out) {
  const MirTyData *data = mir_ty_data(module, type);
  const char *scalar = scalar_name((MirTyKind)data->kind);
  if (scalar != NULL) {
    put_text(out, scalar);
    return;
  }
  switch ((MirTyKind)data->kind) {
  case MK_TYPE: put_name(module, out, module->type_defs.ptr[data->id].name); break;
  case MK_ALT: put_name(module, out, module->alts.ptr[data->id].name); break;
  case MK_LIST:
  case MK_OPT:
    put_text(out, data->kind == MK_LIST ? "list<" : "opt<");
    mir_print_ty(module, data->elem, out);
    ms_strbuild_append_byte(out, '>');
    break;
  case MK_OBJ: print_obj(module, data, out); break;
  case MK_FN: print_fn(module, data, out); break;
  default:
    put_text(out, "dyn ");
    put_name(module, out, module->ifaces.ptr[data->id].name);
    break;
  }
}

void mir_print_ty(const MirModule *module, MirTy type, MsStrBuild *out) {
  print_unscoped(module, mir_ty_unscoped(type), out);
  if (mir_ty_scope(type) != 0) {
    ms_strbuild_printf(out, "@%u", mir_ty_scope(type));
  }
}

void mir_print_quoted(MsStrBuild *out, MsSpan text) {
  ms_strbuild_append_byte(out, '"');
  for (size_t index = 0; index < text.len; index++) {
    const uint8_t byte = text.ptr[index];
    switch (byte) {
    case '"': put_text(out, "\\\""); break;
    case '\\': put_text(out, "\\\\"); break;
    case '\n': put_text(out, "\\n"); break;
    case '\t': put_text(out, "\\t"); break;
    case '\r': put_text(out, "\\r"); break;
    default:
      if (byte < 0x20 || byte == 0x7f) {
        ms_strbuild_printf(out, "\\x%02x", byte);
      } else {
        ms_strbuild_append_byte(out, byte);
      }
    }
  }
  ms_strbuild_append_byte(out, '"');
}

MsSpan mir_cc_name(MirCc cc) {
  static const char *const names[] = {"eq", "ne", "lt", "le", "gt", "ge"};
  return ms_span_of_text(names[cc]);
}

static const char *const role_names[] = {
    [MR_BORROWS_ARGUMENT] = "borrows_argument", [MR_STRBUILDER_APPEND] = "strbuilder_append",
    [MR_STRBUILDER_APPEND_INT] = "strbuilder_append_int", [MR_STRING_CONCAT] = "string_concat",
    [MR_STRING_JOIN] = "string_join", [MR_STRING_APPEND] = "string_append",
    [MR_INT_TO_STRING] = "int_to_string", [MR_LIST_SORTED] = "list_sorted", [MR_RAW_SLOTS] = "raw_slots",
    [MR_RAW_FREE] = "raw_free", [MR_LIST_SORT_INTS] = "list_sort_ints",
    [MR_LIST_SORTED_BY_DIFFERENCE] = "list_sorted_by_difference", [MR_LIST_NEW] = "list_new",
    [MR_MAP_NEW] = "map_new", [MR_BYTES_VALUES] = "bytes_values", [MR_STRING_EQ] = "string_eq",
    [MR_CLEANUP_DISCARD] = "cleanup_discard", [MR_BYTES_APPEND] = "bytes_append",
    [MR_VIEW_RESULT] = "view_result", [MR_TAKES_DYING] = "takes_dying", [MR_SPAWNS_TASK] = "spawns_task",
    [MR_SHIELD_ENTER] = "shield_enter", [MR_SHIELD_EXIT] = "shield_exit", [MR_UNWINDING] = "unwinding",
    [MR_MAP_PROBE_INT] = "map_probe_int", [MR_MAP_PROBE_STR] = "map_probe_str",
    [MR_SET_PROBE_INT] = "set_probe_int", [MR_STRING_SLICE] = "string_slice",
    [MR_BYTES_READ_WORD] = "bytes_read_word", [MR_BYTES_INDEX_OF_BYTE] = "bytes_index_of_byte",
    [MR_STRING_PARSE_INT] = "string_parse_int", [MR_STRING_CONTAINS] = "string_contains",
    [MR_STRING_STARTS_WITH] = "string_starts_with", [MR_STRING_ENDS_WITH] = "string_ends_with",
    [MR_STRING_COMPARE] = "string_compare", [MR_STRING_SCALAR_STEP] = "string_scalar_step",
    [MR_STRING_SCALAR_AT] = "string_scalar_at"};

MsSpan mir_role_name(MirRole role) {
  const char *name = (size_t)role < MS_COUNT_OF(role_names) ? role_names[role] : NULL;
  return name != NULL ? ms_span_of_text(name) : (MsSpan){0};
}

/* A finite float as the shortest text that reads back, with a fractional part. */
void mir_print_float(MsStrBuild *out, double value) {
  uint8_t text[64];
  size_t length = 0;
  if (!ms_fmt_float(value, text, sizeof text, &length)) {
    return;
  }
  bool plain = true;
  for (size_t index = 0; index < length; index++) {
    plain = plain && text[index] != '.' && text[index] != 'e';
  }
  ms_strbuild_append(out, ms_span_of(text, length));
  put_text(out, plain ? ".0" : "");
}

/* compiler/mir/mir_print.c: the declarations of a module in text form. */
#include "compiler/mir/mir_print.h"

static void put_text(MsStrBuild *out, const char *text) {
  ms_strbuild_append_text(out, text);
}

static void put_name(const MirModule *module, MsStrBuild *out, MsName name) {
  ms_strbuild_append(out, ms_names_span(&module->names, name));
}

static void put_list_sep(MsStrBuild *out, size_t index) {
  put_text(out, index > 0 ? ", " : "");
}

static const char *std_name(uint8_t std) {
  switch (std) {
  case MSTD_RESULT: return "result";
  case MSTD_COMPARABLE: return "comparable";
  case MSTD_EQUAL: return "equal";
  default: return NULL;
  }
}

static void print_files(const MirModule *module, MsStrBuild *out) {
  for (size_t index = 0; index < module->files.len; index++) {
    ms_strbuild_printf(out, "file %zu ", index);
    mir_print_quoted(out, module->files.ptr[index]);
    ms_strbuild_append_byte(out, '\n');
  }
  for (size_t index = 0; index < module->blobs.len; index++) {
    ms_strbuild_printf(out, "blob %zu \"", index);
    for (size_t byte = 0; byte < module->blobs.ptr[index].len; byte++) {
      ms_strbuild_printf(out, "%02x", module->blobs.ptr[index].ptr[byte]);
    }
    put_text(out, "\"\n");
  }
  for (size_t index = 0; index < module->list_consts.len; index++) {
    const MirListConst *list = &module->list_consts.ptr[index];
    ms_strbuild_printf(out, "consts %zu [", index);
    for (uint32_t item = 0; item < list->count; item++) {
      put_list_sep(out, item);
      ms_strbuild_append_i64(out, module->list_const_values.ptr[list->start + item]);
    }
    put_text(out, "]\n");
  }
}

static void print_fields(const MirModule *module, MsStrBuild *out, const MirField *fields, uint32_t count) {
  for (uint32_t index = 0; index < count; index++) {
    put_list_sep(out, index);
    put_name(module, out, fields[index].name);
    put_text(out, ": ");
    mir_print_ty(module, fields[index].ty, out);
  }
}

static void print_types(const MirModule *module, MsStrBuild *out) {
  for (size_t index = 0; index < module->type_defs.len; index++) {
    const MirTypeDef *def = &module->type_defs.ptr[index];
    put_text(out, "type ");
    put_name(module, out, def->name);
    put_text(out, def->indirect ? " indirect { " : " { ");
    print_fields(module, out, def->fields, def->nfields);
    put_text(out, " }\n");
  }
}

static void print_alts(const MirModule *module, MsStrBuild *out) {
  for (size_t index = 0; index < module->alts.len; index++) {
    const MirAltDef *alt = &module->alts.ptr[index];
    put_text(out, "alt ");
    put_name(module, out, alt->name);
    if (alt->borrowed != 0) {
      ms_strbuild_printf(out, " borrowed %llu", (unsigned long long)alt->borrowed);
    }
    put_text(out, " { ");
    for (uint32_t c = 0; c < alt->ncases; c++) {
      put_list_sep(out, c);
      put_name(module, out, alt->cases[c].name);
      if (alt->cases[c].nfields > 0) {
        ms_strbuild_append_byte(out, '(');
        print_fields(module, out, alt->cases[c].fields, alt->cases[c].nfields);
        ms_strbuild_append_byte(out, ')');
      }
    }
    put_text(out, " }");
    if (std_name(alt->std) != NULL) {
      ms_strbuild_printf(out, " %s", std_name(alt->std));
    }
    ms_strbuild_append_byte(out, '\n');
  }
}

static void print_ifaces(const MirModule *module, MsStrBuild *out) {
  for (size_t index = 0; index < module->ifaces.len; index++) {
    const MirIfaceDef *iface = &module->ifaces.ptr[index];
    put_text(out, "iface ");
    put_name(module, out, iface->name);
    put_text(out, " { ");
    for (uint32_t m = 0; m < iface->nmethods; m++) {
      const MirMethodSig *sig = &iface->methods[m];
      put_list_sep(out, m);
      put_name(module, out, sig->name);
      ms_strbuild_append_byte(out, '(');
      for (uint32_t p = 0; p < sig->nparams; p++) {
        put_list_sep(out, p);
        put_text(out, mir_owns(sig->owned, p) ? "move " : "");
        mir_print_ty(module, sig->params[p], out);
      }
      put_text(out, ") -> ");
      mir_print_ty(module, sig->ret, out);
    }
    put_text(out, " }");
    if (std_name(iface->std) != NULL) {
      ms_strbuild_printf(out, " %s", std_name(iface->std));
    }
    ms_strbuild_append_byte(out, '\n');
  }
}

static void print_extern_flags(const MirExtern *external, MsStrBuild *out) {
  put_text(out, external->pure ? " pure" : "");
  put_text(out, external->noreturn ? " noreturn" : "");
  put_text(out, external->fresh ? " fresh" : "");
  put_text(out, external->leaf ? " leaf" : "");
  put_text(out, external->reads ? " reads" : "");
  put_text(out, external->retains ? " retains" : "");
  const MsSpan role = mir_role_name((MirRole)external->role);
  if (role.len != 0) {
    ms_strbuild_append_byte(out, ' ');
    ms_strbuild_append(out, role);
  }
}

static void print_externs(const MirModule *module, MsStrBuild *out) {
  for (size_t index = 0; index < module->externs.len; index++) {
    const MirExtern *external = &module->externs.ptr[index];
    put_text(out, "extern @");
    put_name(module, out, external->name);
    ms_strbuild_append_byte(out, '(');
    for (uint32_t p = 0; p < external->nparams; p++) {
      put_list_sep(out, p);
      put_text(out, external->params[p].mode == MM_MOVE ? "move " : "");
      mir_print_ty(module, external->params[p].ty, out);
    }
    put_text(out, ") -> ");
    mir_print_ty(module, external->ret, out);
    print_extern_flags(external, out);
    ms_strbuild_append_byte(out, '\n');
  }
}

static void print_data(const MirModule *module, MsStrBuild *out) {
  for (size_t index = 0; index < module->globals.len; index++) {
    put_text(out, "global @");
    put_name(module, out, module->globals.ptr[index].name);
    put_text(out, ": ");
    mir_print_ty(module, module->globals.ptr[index].ty, out);
    ms_strbuild_append_byte(out, '\n');
  }
  for (size_t index = 0; index < module->vtables.len; index++) {
    const MirVtable *vtable = &module->vtables.ptr[index];
    put_text(out, "vtable @");
    put_name(module, out, vtable->name);
    put_text(out, ": ");
    put_name(module, out, module->ifaces.ptr[vtable->iface].name);
    put_text(out, " for ");
    mir_print_ty(module, vtable->data_ty, out);
    put_text(out, " { ");
    for (uint32_t m = 0; m < vtable->nmethods; m++) {
      put_text(out, m > 0 ? ", @" : "@");
      put_name(module, out, module->funcs.ptr[vtable->methods[m]].name);
    }
    put_text(out, " }\n");
  }
  for (size_t index = 0; index < module->desc_glue.len; index++) {
    const MirDescGlue *glue = &module->desc_glue.ptr[index];
    put_text(out, "desc_glue ");
    mir_print_ty(module, glue->ty, out);
    put_text(out, " @");
    put_name(module, out, module->funcs.ptr[glue->eq].name);
    put_text(out, " @");
    put_name(module, out, module->funcs.ptr[glue->hash].name);
    ms_strbuild_append_byte(out, '\n');
  }
}

void mir_print_module(const MirModule *module, MsStrBuild *out) {
  put_text(out, "module ");
  mir_print_quoted(out, ms_names_span(&module->names, module->name));
  ms_strbuild_append_byte(out, '\n');
  print_files(module, out);
  print_types(module, out);
  print_alts(module, out);
  print_ifaces(module, out);
  print_externs(module, out);
  print_data(module, out);
  if (module->entry != MIR_NONE) {
    put_text(out, "entry @");
    put_name(module, out, module->funcs.ptr[module->entry].name);
    ms_strbuild_append_byte(out, '\n');
  }
  if (module->close != MIR_NONE) {
    put_text(out, "close @");
    put_name(module, out, module->funcs.ptr[module->close].name);
    ms_strbuild_append_byte(out, '\n');
  }
  for (size_t index = 0; index < module->funcs.len; index++) {
    ms_strbuild_append_byte(out, '\n');
    mir_print_func(module, &module->funcs.ptr[index], out);
  }
}

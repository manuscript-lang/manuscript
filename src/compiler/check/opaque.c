/* An `opaque` type or enum may be built, read, destructured and matched only in the module that declares it. */
#include "compiler/check/body.h"
#include "compiler/check/properties.h"

bool body_opaque_denied(Body *body, MsPos pos, MsTy ty, MsSpan what) {
  const MsTyTable *types = &body->program->types;
  const MsDef *def = body_def(body, ty);
  if (body->module >= body->program->user_modules || body->quiet || def == NULL || !ms_check_def_opaque(body->program, def)) {
    return false;
  }
  const MsSymbol *home = &body->program->symbols.ptr[def->symbol];
  if (home->module == body->module) {
    return false;
  }
  const MsSpan file = ms_names_span(body->program->names, body->program->modules.ptr[home->module].file);
  MsStrBuild text = ms_strbuild_new();
  ms_ty_show(&text, body->program->names, types, ty);
  ms_strbuild_append_text(&text, " is opaque outside ");
  ms_strbuild_append(&text, file);
  ms_strbuild_append_text(&text, ": ");
  ms_strbuild_append(&text, what);
  ms_strbuild_append_text(&text, "; use the functions ");
  ms_strbuild_append(&text, file);
  ms_strbuild_append_text(&text, " exports");
  ms_check_report(body->program, body->module, pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  return true;
}

/* compiler/own/look_fields.c: see look_fields.h. */
#include "compiler/own/look_fields.h"

#include "compiler/check/properties.h"

/* The declaration of the record type a constructor call builds, found through the type's definition: scanning the
 * module's declarations for it made every constructor argument cost the size of the module. */
static const MsDecl *constructed_decl(const MsCheckProgram *program, const MsCall *call) {
  if (call->callee.kind != MS_REF_TYPE || call->callee.decl.module >= program->modules.len) {
    return NULL;
  }
  const MsTyRow *row = ms_ty_row(&program->types, ms_ty_result(&program->types, call->callee_ty));
  if (row->kind != MS_TY_TYPE || row->def == 0) {
    return NULL;
  }
  const MsSymbol *symbol = &program->symbols.ptr[ms_defs_get(&program->defs, row->def)->symbol];
  const MsDecl *decl = symbol->decl;
  return decl != NULL && decl->kind == MS_D_TYPE && symbol->module == call->callee.decl.module &&
                 decl->id == call->callee.decl.node
             ? decl
             : NULL;
}

bool ms_own_look_field(const MsCheckProgram *program, const MsCall *call, uint32_t index) {
  const MsDecl *decl = constructed_decl(program, call);
  return decl != NULL && index < decl->u.type.fields.len && decl->u.type.fields.ptr[index]->ty != NULL &&
         decl->u.type.fields.ptr[index]->ty->is_ref;
}

bool ms_own_look_record(const MsCheckProgram *program, MsTy ty) {
  return ms_check_look_record(program, ty);
}

bool ms_own_look_carrier(const MsCheckProgram *program, const MsCall *call, uint32_t index) {
  if (call->callee.kind != MS_REF_TYPE) {
    return false;
  }
  const MsTyRow *row = ms_ty_row(&program->types, ms_ty_result(&program->types, call->callee_ty));
  if (row->kind != MS_TY_TYPE || row->def == 0) {
    return false;
  }
  const MsDef *def = ms_defs_get(&program->defs, row->def);
  return index < def->fields.len && ms_check_look_record(program, def->fields.ptr[index].ty);
}

bool ms_own_look_member(const MsCheckProgram *program, const MsFacts *facts, const MsExpr *member) {
  const MsTy record = ms_facts_type(facts, member->u.member.left->id);
  const MsTyRow *row = record == MS_TY_NONE ? NULL : ms_ty_row(&program->types, record);
  if (row == NULL || row->kind != MS_TY_TYPE || row->def == 0) {
    return false;
  }
  const MsDef *def = ms_defs_get(&program->defs, row->def);
  const MsDecl *decl = program->symbols.ptr[def->symbol].decl;
  for (uint32_t index = 0; decl != NULL && decl->kind == MS_D_TYPE && index < decl->u.type.fields.len && index < def->fields.len; index++) {
    if (def->fields.ptr[index].name == member->u.member.name) {
      return decl->u.type.fields.ptr[index]->ty != NULL && decl->u.type.fields.ptr[index]->ty->is_ref;
    }
  }
  return false;
}

/* Owns the written-type and type-parameter occurrences of occurrence.h. */
#include "tooling/occurrence.h"
#include "tooling/occurrence_private.h"

#include "base/message.h"
#include "base/sort.h"
#include "compiler/check/methods.h"
#include "compiler/syntax/walk.h"
#include "tooling/facts.h"

/* ---- written types ---- */

static void type_site(Builder *b, const MsTypeRef *type) {
  type_sites_push(b->arena, b->sink, (TypeSite){.id = type->id, .offset = type->pos.offset, .name = type->name, .named = type->kind == MS_TYPE_NAMED});
  if (type->kind == MS_TYPE_NAMED) {
    for (uint32_t index = 0; index < type->args.len; index++) {
      type_site(b, type->args.ptr[index]);
    }
  } else {
    for (uint32_t index = 0; index < type->params.len; index++) {
      if (type->params.ptr[index]->ty != NULL) {
        type_site(b, type->params.ptr[index]->ty);
      }
    }
    if (type->result != NULL) {
      type_site(b, type->result);
    }
  }
}

/* A written type that names a nominal type is an occurrence of it. */
static void emit_type_sites(Builder *b, const TypeSites *sites) {
  for (size_t index = 0; index < sites->len; index++) {
    const TypeSite *site = &sites->ptr[index];
    const MsTy resolved = site->id < b->program->modules.ptr[b->module].tree->node_count ? b->written[b->module][site->id] : MS_TY_NONE;
    const MsSymbolId symbol = site->named ? ms_occ_type_symbol(b, resolved) : 0;
    if (symbol != 0) {
      ms_occ_add(b, ms_occ_symbol_key(b, symbol), ms_occ_name_text(b, site->name), b->module, site->offset, false, false, resolved, symbol, false);
    }
  }
}

static void param_sites(Builder *b, MsParams params) {
  for (uint32_t index = 0; index < params.len; index++) {
    if (params.ptr[index]->ty != NULL) {
      type_site(b, params.ptr[index]->ty);
    }
  }
}

static void type_param_sites(Builder *b, MsTypeParams params) {
  for (uint32_t index = 0; index < params.len; index++) {
    for (uint32_t bound = 0; bound < params.ptr[index]->bounds.len; bound++) {
      type_site(b, params.ptr[index]->bounds.ptr[bound]);
    }
    if (params.ptr[index]->def != NULL) {
      type_site(b, params.ptr[index]->def);
    }
  }
}

static void func_sites(Builder *b, const MsFunc *func) {
  type_param_sites(b, func->type_params);
  param_sites(b, func->params);
  if (func->result != NULL) {
    type_site(b, func->result);
  }
}

static void body_types_stmt(void *context, const MsStmt *stmt) {
  Builder *b = context;
  if (stmt->kind == MS_S_BIND && stmt->u.bind.ty != NULL) {
    type_site(b, stmt->u.bind.ty);
  }
}

static void arm_path_types(Builder *b, const MsExpr *path) {
  if (path->kind == MS_E_APPLY) {
    for (uint32_t index = 0; index < path->u.apply.types.len; index++) {
      type_site(b, path->u.apply.types.ptr[index]);
    }
    arm_path_types(b, path->u.apply.left);
  } else if (path->kind == MS_E_MEMBER) {
    arm_path_types(b, path->u.member.left);
  }
}

static void body_types_expr(void *context, const MsExpr *expr) {
  Builder *b = context;
  if (expr->kind == MS_E_APPLY) {
    for (uint32_t index = 0; index < expr->u.apply.types.len; index++) {
      type_site(b, expr->u.apply.types.ptr[index]);
    }
  } else if (expr->kind == MS_E_LAMBDA) {
    param_sites(b, expr->u.lambda.params);
    if (expr->u.lambda.result != NULL) {
      type_site(b, expr->u.lambda.result);
    }
  } else if (expr->kind == MS_E_MATCH) {
    for (uint32_t index = 0; index < expr->u.match.arms.len; index++) {
      arm_path_types(b, expr->u.match.arms.ptr[index]->path);
    }
  }
}

void ms_occ_declare_types(Builder *b, uint32_t module) {
  b->module = module;
  TypeSites sites = {0};
  b->sink = &sites;
  const MsModule *tree = b->program->modules.ptr[module].tree;
  const MsVisitor visitor = {.ctx = b, .stmt = body_types_stmt, .expr = body_types_expr};
  for (uint32_t at = 0; at < tree->ndecls; at++) {
    const MsDecl *decl = tree->decls[at];
    switch ((MsDeclKind)decl->kind) {
    case MS_D_FN:
      func_sites(b, &decl->u.fn);
      break;
    case MS_D_CONST:
      if (decl->u.konst.ty != NULL) {
        type_site(b, decl->u.konst.ty);
      }
      break;
    case MS_D_TYPE:
      type_param_sites(b, decl->u.type.type_params);
      param_sites(b, decl->u.type.fields);
      break;
    case MS_D_ENUM:
      type_param_sites(b, decl->u.enumeration.type_params);
      for (uint32_t index = 0; index < decl->u.enumeration.cases.len; index++) {
        param_sites(b, decl->u.enumeration.cases.ptr[index]->fields);
      }
      break;
    case MS_D_ALIAS:
      type_param_sites(b, decl->u.alias.type_params);
      for (uint32_t index = 0; index < decl->u.alias.targets.len; index++) {
        type_site(b, decl->u.alias.targets.ptr[index]);
      }
      break;
    case MS_D_INTERFACE:
      type_param_sites(b, decl->u.iface.type_params);
      for (uint32_t index = 0; index < decl->u.iface.methods.len; index++) {
        func_sites(b, &decl->u.iface.methods.ptr[index]->func);
      }
      break;
    case MS_D_IMPL:
      /* The first method of a receiver form writes it as a type; the rest are folded into that one. */
      if (b->folded_into[module][at] == at) {
        type_site(b, decl->u.impl.receiver);
      }
      for (uint32_t index = 0; index < decl->u.impl.methods.len; index++) {
        func_sites(b, &decl->u.impl.methods.ptr[index]->func);
      }
      break;
    case MS_D_TEST:
      break;
    }
    ms_walk_decl(&visitor, decl);
  }
  emit_type_sites(b, &sites);
}

/* ---- type parameters ---- */

/* The written name declares a type parameter and every use inside its declaration resolves to it, so they navigate
 * like locals. */
typedef struct ParamSite {
  MsName name;
  uint32_t offset;   /* the written name */
  uint32_t declared; /* the declaring name, which identifies the parameter */
  bool declaration;
  bool has_checked;  /* a use whose resolution the checker recorded */
  uint32_t checked;
} ParamSite;

MS_AVEC(ParamSites, param_sites_list, ParamSite)

enum { SCOPE_MAX = 48 };

typedef struct ParamScope {
  MsName name[SCOPE_MAX];
  uint32_t declared[SCOPE_MAX];
  size_t len;
} ParamScope;

static void scope_push(ParamScope *scope, MsName name, uint32_t declared) {
  if (scope->len < SCOPE_MAX) {
    scope->name[scope->len] = name;
    scope->declared[scope->len] = declared;
    scope->len++;
  }
}

static void scope_declare(Builder *b, ParamScope *scope, ParamSites *out, MsName name, uint32_t offset) {
  scope_push(scope, name, offset);
  param_sites_list_push(b->arena, out, (ParamSite){.name = name, .offset = offset, .declared = offset, .declaration = true});
}

static void scope_declare_all(Builder *b, ParamScope *scope, ParamSites *out, MsTypeParams params) {
  for (uint32_t index = 0; index < params.len; index++) {
    scope_declare(b, scope, out, params.ptr[index]->name, params.ptr[index]->pos.offset);
  }
}

static void scope_uses(Builder *b, const ParamScope *scope, const TypeSites *sites, size_t from, bool checked, ParamSites *out) {
  for (size_t index = from; index < sites->len; index++) {
    const TypeSite *site = &sites->ptr[index];
    for (size_t at = scope->len; site->named && at > 0; at--) {
      if (scope->name[at - 1] == site->name) {
        param_sites_list_push(b->arena, out, (ParamSite){.name = site->name, .offset = site->offset, .declared = scope->declared[at - 1],
                                                          .has_checked = checked, .checked = site->id});
        break;
      }
    }
  }
}

static void collect_type_params(Builder *b, MsTypeParams params) {
  type_param_sites(b, params);
}

/* The type sites of one function: its signature and the annotations in its body. */
static TypeSites function_sites(Builder *b, const MsFunc *func) {
  TypeSites sites = {0};
  TypeSites *saved = b->sink;
  b->sink = &sites;
  func_sites(b, func);
  const MsVisitor visitor = {.ctx = b, .stmt = body_types_stmt, .expr = body_types_expr};
  ms_walk_callable(&visitor, func->params, func->body);
  b->sink = saved;
  return sites;
}

static void method_scopes(Builder *b, const ParamScope *outer, MsMethod *const *methods, uint32_t count, ParamSites *out) {
  for (uint32_t index = 0; index < count; index++) {
    ParamScope scope = *outer;
    TypeSites receiver = {0};
    TypeSites *saved = b->sink;
    b->sink = &receiver;
    for (uint32_t at = 0; at < methods[index]->receiver_args.len; at++) {
      type_site(b, methods[index]->receiver_args.ptr[at]);
    }
    b->sink = saved;
    scope_uses(b, &scope, &receiver, 0, false, out);
    scope_declare_all(b, &scope, out, methods[index]->func.type_params);
    const TypeSites own = function_sites(b, &methods[index]->func);
    scope_uses(b, &scope, &own, 0, true, out);
  }
}

/* The type a module declares as `name`, for the parameters a receiver writes. */
static MsTypeParams declared_type_params(const MsModule *tree, MsName name, bool *found) {
  for (uint32_t at = 0; at < tree->ndecls; at++) {
    const MsDecl *decl = tree->decls[at];
    if (decl->kind == MS_D_TYPE && decl->u.type.name == name) {
      *found = true;
      return decl->u.type.type_params;
    }
    if (decl->kind == MS_D_ENUM && decl->u.enumeration.name == name) {
      *found = true;
      return decl->u.enumeration.type_params;
    }
  }
  *found = false;
  return (MsTypeParams){0};
}

static void type_parameter_sites(Builder *b, uint32_t module, ParamSites *out) {
  b->module = module;
  const MsModule *tree = b->program->modules.ptr[module].tree;
  ParamScope *scopes = MS_ARENA_NEW_ARRAY(b->arena, ParamScope, tree->ndecls + 1);
  for (uint32_t at = 0; at < tree->ndecls; at++) {
    const MsDecl *decl = tree->decls[at];
    if (decl->synthetic && decl->kind == MS_D_INTERFACE) {
      continue;
    }
    ParamScope scope = {0};
    TypeSites sites = {0};
    b->sink = &sites;
    const bool folded = decl->kind == MS_D_IMPL && b->folded_into[module][at] != at;
    if (folded) {
      scope = scopes[b->folded_into[module][at]];
    }
    switch (folded ? MS_D_TEST : (MsDeclKind)decl->kind) {
    case MS_D_FN: {
      scope_declare_all(b, &scope, out, decl->u.fn.type_params);
      const TypeSites own = function_sites(b, &decl->u.fn);
      scope_uses(b, &scope, &own, 0, true, out);
      break;
    }
    case MS_D_TYPE:
      scope_declare_all(b, &scope, out, decl->u.type.type_params);
      collect_type_params(b, decl->u.type.type_params);
      param_sites(b, decl->u.type.fields);
      break;
    case MS_D_ENUM:
      scope_declare_all(b, &scope, out, decl->u.enumeration.type_params);
      collect_type_params(b, decl->u.enumeration.type_params);
      for (uint32_t index = 0; index < decl->u.enumeration.cases.len; index++) {
        param_sites(b, decl->u.enumeration.cases.ptr[index]->fields);
      }
      break;
    case MS_D_ALIAS:
      scope_declare_all(b, &scope, out, decl->u.alias.type_params);
      collect_type_params(b, decl->u.alias.type_params);
      for (uint32_t index = 0; index < decl->u.alias.targets.len; index++) {
        type_site(b, decl->u.alias.targets.ptr[index]);
      }
      break;
    case MS_D_INTERFACE:
      scope_declare_all(b, &scope, out, decl->u.iface.type_params);
      collect_type_params(b, decl->u.iface.type_params);
      break;
    case MS_D_IMPL: {
      /* The receiver's bare arguments name the parameters of the type it extends (`fn Gen[T].map` uses `T` of
       * `type Gen[T]`); a receiver whose type is declared elsewhere declares them here. */
      TypeSites receiver = {0};
      b->sink = &receiver;
      type_site(b, decl->u.impl.receiver);
      b->sink = &sites;
      if (decl->u.impl.receiver->kind == MS_TYPE_NAMED) {
        bool found = false;
        const MsTypeParams declared = declared_type_params(tree, decl->u.impl.receiver->name, &found);
        for (uint32_t index = 0; index < decl->u.impl.receiver->args.len; index++) {
          const MsTypeRef *arg = decl->u.impl.receiver->args.ptr[index];
          if (arg->kind != MS_TYPE_NAMED || arg->args.len != 0) {
            continue;
          }
          if (found && index < declared.len) {
            if (declared.ptr[index]->name == arg->name) {
              scope_push(&scope, arg->name, declared.ptr[index]->pos.offset);
            }
          } else if (!found || index >= declared.len) {
            scope_declare(b, &scope, out, arg->name, arg->pos.offset);
          }
        }
      }
      scope_uses(b, &scope, &receiver, 1, true, out);
      for (uint32_t index = 0; index < decl->u.impl.bounds.len; index++) {
        TypeSites bounds = {0};
        b->sink = &bounds;
        for (uint32_t bound = 0; bound < decl->u.impl.bounds.ptr[index]->bounds.len; bound++) {
          type_site(b, decl->u.impl.bounds.ptr[index]->bounds.ptr[bound]);
        }
        b->sink = &sites;
        scope_uses(b, &scope, &bounds, 0, true, out);
      }
      break;
    }
    case MS_D_CONST:
    case MS_D_TEST:
      break;
    }
    scopes[at] = scope;
    scope_uses(b, &scope, &sites, 0, true, out);
    if (decl->kind == MS_D_INTERFACE) {
      method_scopes(b, &scope, decl->u.iface.methods.ptr, decl->u.iface.methods.len, out);
    } else if (decl->kind == MS_D_IMPL) {
      method_scopes(b, &scope, decl->u.impl.methods.ptr, decl->u.impl.methods.len, out);
    }
  }
}

MS_MAP_DEFINE(OffsetTypes, offset_types, uint32_t, MsTy, ms_hash_u32_key, ms_equal_u32_key)

void ms_occ_declare_type_parameters(Builder *b, uint32_t module) {
  ParamSites found = {0};
  type_parameter_sites(b, module, &found);
  b->module = module;
  const MsFacts *facts = &b->program->modules.ptr[module].facts;
  (void)facts;
  OffsetTypes first = {0};
  MsTy *own = MS_ARENA_NEW_ARRAY(b->arena, MsTy, found.len + 1);
  bool *skip = MS_ARENA_NEW_ARRAY(b->arena, bool, found.len + 1);
  for (size_t index = 0; index < found.len; index++) {
    const ParamSite *site = &found.ptr[index];
    if (site->has_checked) {
      const MsTy ty = site->checked < b->program->modules.ptr[module].tree->node_count ? b->written[module][site->checked] : MS_TY_NONE;
      if (ty == MS_TY_NONE || ms_ty_kind(&b->program->types, ty) != MS_TY_VARIABLE) {
        skip[index] = true;
        continue;
      }
      own[index] = ty;
      if (offset_types_get(&first, site->declared) == NULL) {
        offset_types_put(&first, site->declared, ty);
      }
    }
  }
  for (size_t index = 0; index < found.len; index++) {
    const ParamSite *site = &found.ptr[index];
    if (skip[index]) {
      continue;
    }
    MsTy ty = own[index];
    if (ty == MS_TY_NONE) {
      const MsTy *known = offset_types_get(&first, site->declared);
      ty = known == NULL ? MS_TY_NONE : *known;
    }
    ms_occ_add(b, ms_message_format(b->arena, "binding:typeparam:%S:%u", ms_occ_module_file(b, module), site->declared), ms_occ_name_text(b, site->name),
        module, site->offset, site->declaration, false, ty, 0, false);
  }
  offset_types_free(&first);
}

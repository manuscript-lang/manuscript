/* compiler/check/test_fixture.c: the `make_fixture` factory of a test file and the `fixture` its tests see. */
#include "compiler/check/body.h"
#include "compiler/check/methods.h"

static MsName fixture_name(const Body *body, const char *text) {
  return ms_names_intern(body->program->names, ms_span_of_text(text));
}

/* The module's `make_fixture` function, or NULL when it declares none. */
static const MsSymbol *factory_symbol(const Body *body) {
  const MsSymbolId *found = ms_scope_get(&body->program->modules.ptr[body->module].scope, fixture_name(body, "make_fixture"));
  return found != NULL ? &body->program->symbols.ptr[*found] : NULL;
}

/* The interface `TestHooks` of @std/test/test.ms, or MS_TY_NONE when that module is not loaded. */
static MsTy hooks_type(const Body *body) {
  const MsCheckProgram *program = body->program;
  const MsName home = fixture_name(body, "@std/test/test.ms");
  for (uint32_t index = 0; index < program->modules.len; index++) {
    const MsSymbolId *found = program->modules.ptr[index].id == home
                                  ? ms_scope_get(&program->modules.ptr[index].scope, fixture_name(body, "TestHooks"))
                                  : NULL;
    if (found != NULL) {
      return program->symbols.ptr[*found].ty;
    }
  }
  return MS_TY_NONE;
}

static void report(Body *body, const MsSymbol *factory, const char *message) {
  ms_check_report(body->program, body->module, factory->decl->pos, MS_CHECK_TYPE, ms_string_from_span(ms_span_of_text(message)));
}

void ms_check_test_fixture(Body *body) {
  const MsSymbol *factory = factory_symbol(body);
  if (factory == NULL || factory->kind != MS_SYMBOL_FN || factory->decl == NULL || factory->ty == MS_TY_NONE) {
    return;
  }
  MsTyTable *types = &body->program->types;
  if (factory->decl->kind != MS_D_FN || factory->var_count != 0 || ms_ty_param_count(types, factory->ty) != 0) {
    report(body, factory, "make_fixture must be a nongeneric zero-argument function; declare fn make_fixture() ConcreteFixture");
    return;
  }
  const MsTy result = ms_ty_result(types, factory->ty);
  const MsTy hooks = hooks_type(body);
  if (result == MS_TY_NONE || hooks == MS_TY_NONE || !ms_check_shape_optional(body->program, result, hooks)) {
    report(body, factory,
           "make_fixture must return a concrete type implementing @std/test/test.ms TestHooks; return your fixture type and declare any of fn var Fixture.before_all(), before_each(), after_each() and after_all() with no arguments returning Void!");
    return;
  }
  body->fixture_ty = result;
}

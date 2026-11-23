/* Owns the effect patterns of package.h and the check of what a project allows a package. */
#include "base/message.h"
#include "compiler/project/attach_internal.h"

bool ms_package_pattern_covers(MsSpan allowed, MsSpan declared) {
  if (ms_span_is_text(allowed, "*") || ms_span_equal(allowed, declared)) {
    return true;
  }
  if (ms_span_ends_with(allowed, ms_span_of_text(".*"))) {
    const MsSpan prefix = ms_span_of(allowed.ptr, allowed.len - 2);
    return ms_span_equal(declared, prefix) ||
           (ms_span_starts_with(declared, prefix) && declared.len > prefix.len && declared.ptr[prefix.len] == '.');
  }
  if (ms_span_starts_with(allowed, ms_span_of_text("*."))) {
    const MsSpan suffix = ms_span_of(allowed.ptr + 1, allowed.len - 1); /* `.name` */
    size_t at = 0;
    return !ms_span_find(declared, ms_span_of_text("*"), &at) && ms_span_ends_with(declared, suffix);
  }
  return false;
}

bool ms_package_uncovered(const MsSpan *allowed, size_t nallowed, const MsSpan *declared, size_t ndeclared,
                          MsSpan *missing) {
  for (size_t i = 0; i < ndeclared; i++) {
    bool covered = false;
    for (size_t j = 0; j < nallowed; j++) {
      covered = covered || ms_package_pattern_covers(allowed[j], declared[i]);
    }
    if (!covered) {
      *missing = declared[i];
      return true;
    }
  }
  return false;
}

static const MsAllowedEffects *allowed_for(const MsManifest *scope, MsSpan alias) {
  for (size_t i = 0; i < scope->allowed_effects.len; i++) {
    if (ms_span_equal(scope->allowed_effects.ptr[i].name, alias)) {
      return &scope->allowed_effects.ptr[i];
    }
  }
  return NULL;
}

static MsSpan debug_list(MsArena *arena, const MsSpan *items, size_t count) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_byte(&text, '[');
  for (size_t i = 0; i < count; i++) {
    ms_strbuild_append_text(&text, i == 0 ? "" : ", ");
    ms_strbuild_append(&text, ms_project_quote(arena, items[i]));
  }
  ms_strbuild_append_byte(&text, ']');
  return ms_message_take_builder(arena, &text);
}

bool attach_check_effects(MsArena *arena, const MsManifest *scope, MsSpan alias, MsSpan id, MsSpan asker,
                          const MsManifest *package, MsProjectError *error) {
  const MsSpan prefix = ms_span_of_text("workspace/");
  const MsSpan label = ms_span_starts_with(id, prefix)
                           ? ms_message_format(arena, "workspace member %S", ms_span_of(id.ptr + prefix.len, id.len - prefix.len))
                           : ms_message_format(arena, "package %S", id);
  const MsAllowedEffects *allowed = allowed_for(scope, alias);
  MsSpan missing = {0};
  if (ms_package_uncovered(allowed == NULL ? NULL : allowed->patterns, allowed == NULL ? 0 : allowed->count,
                           package->effects, package->neffects, &missing)) {
    ms_project_error_message(
        error, asker.len == 0
                   ? ms_message_format(arena,
                                       "%S may use %S, which this project does not allow; add `%S = [\"%S\"]` under "
                                       "[effects] in ms.toml if you trust it",
                                       label, missing, alias, missing)
                   : ms_message_format(arena,
                                       "%S may use %S, which %S does not allow for %S; %S would have to allow it "
                                       "under [effects], so ask its author, or require a version of %S that does not "
                                       "use %S",
                                       label, missing, asker, alias, asker, id, missing));
    return false;
  }
  if (asker.len != 0 && ms_package_uncovered(scope->effects, scope->neffects, package->effects, package->neffects,
                                             &missing)) {
    ms_project_error_message(error,
                             ms_message_format(arena,
                                               "%S may use %S, but %S declares only %S; a package cannot hand a "
                                               "dependency effects it does not have itself",
                                               label, missing, asker, debug_list(arena, scope->effects, scope->neffects)));
    return false;
  }
  return true;
}

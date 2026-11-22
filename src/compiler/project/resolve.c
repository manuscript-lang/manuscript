/* compiler/project/resolve.c: local import paths to canonical files inside the project root. */
#include <errno.h>

#include "base/file.h"
#include "base/path.h"
#include "compiler/project/manifest.h"
#include "compiler/project/project_internal.h"

enum { OS_ENOENT = 2, OS_EACCES = 13, OS_ENOTDIR = 20 };

static bool span_less(MsSpan a, MsSpan b) {
  const size_t common = a.len < b.len ? a.len : b.len;
  for (size_t i = 0; i < common; i++) {
    if (a.ptr[i] != b.ptr[i]) {
      return a.ptr[i] < b.ptr[i];
    }
  }
  return a.len < b.len;
}

static bool message(MsArena *arena, MsProjectError *error, MsStrBuild *text) {
  ms_project_error_message(error, ms_project_text(arena, text));
  return false;
}

static bool fail_text(MsArena *arena, MsProjectError *error, const char *text) {
  ms_project_error_message(error, ms_arena_copy(arena, ms_span_of_text(text)));
  return false;
}

static MsSpan directory_of(MsSpan path) {
  const MsSpan parent = ms_path_parent(path);
  if (parent.len == 0 && ms_path_is_absolute(path)) {
    return ms_span_of_text("/");
  }
  return parent;
}

static bool last_element_is_name(MsSpan path) {
  const MsSpan last = ms_path_file_name(path);
  return last.len != 0 && !ms_span_is_text(last, ".") && !ms_span_is_text(last, "..");
}

static bool relative_target(MsArena *arena, MsSpan importer, MsSpan path, MsSpan *target,
                            MsProjectError *error) {
  MsStrBuild text = ms_strbuild_new();
  if (!last_element_is_name(path)) {
    ms_strbuild_append_text(&text, "import path \"");
    ms_strbuild_append(&text, path);
    ms_strbuild_append_text(&text, "\" names a directory, not a module; end it with a file such as \"./name.ms\"");
    return message(arena, error, &text);
  }
  const MsSpan ext = ms_path_ext(path);
  if (!ms_span_is_text(ext, ".ms")) {
    ms_strbuild_append_text(&text, "import path requires .ms extension; write \"");
    ms_strbuild_append(&text, ms_span_of(path.ptr, path.len - ext.len));
    ms_strbuild_append_text(&text, ".ms\"");
    return message(arena, error, &text);
  }
  MsStrBuild joined = ms_strbuild_new();
  ms_path_append_joined(&joined, directory_of(importer), path);
  ms_path_clean(&text, ms_strbuild_span(&joined));
  ms_strbuild_free(&joined);
  *target = ms_project_text(arena, &text);
  return true;
}

/* The declared alias names (aliases and dependencies), each once, in byte order. */
static size_t declared_names(MsArena *arena, const MsManifest *manifest, MsSpan **names) {
  const size_t total = manifest == NULL ? 0 : manifest->aliases.len + manifest->deps.len;
  MsSpan *all = MS_ARENA_NEW_ARRAY(arena, MsSpan, total + 1);
  size_t count = 0;
  for (size_t i = 0; i < total; i++) {
    const MsSpan name = i < manifest->aliases.len ? manifest->aliases.ptr[i].name
                                                  : manifest->deps.ptr[i - manifest->aliases.len].name;
    bool known = false;
    for (size_t j = 0; j < count; j++) {
      known = known || ms_span_equal(all[j], name);
    }
    if (!known) {
      all[count++] = name;
    }
  }
  for (size_t i = 1; i < count; i++) {
    for (size_t j = i; j > 0 && span_less(all[j], all[j - 1]); j--) {
      const MsSpan swap = all[j];
      all[j] = all[j - 1];
      all[j - 1] = swap;
    }
  }
  *names = all;
  return count;
}

static bool unknown_alias(MsArena *arena, const MsManifest *manifest, MsSpan alias, MsProjectError *error) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "unknown import alias ");
  ms_strbuild_append(&text, alias);
  MsSpan *names = NULL;
  const size_t count = declared_names(arena, manifest, &names);
  if (count == 0) {
    ms_strbuild_append_text(&text, "; this project declares none, so add one under [aliases] in ms.toml, e.g. "
                                   "@lib = \"src/lib\" (use @std/... for the standard library)");
    return message(arena, error, &text);
  }
  ms_strbuild_append_text(&text, "; declared aliases: ");
  for (size_t i = 0; i < count; i++) {
    ms_strbuild_append_text(&text, i == 0 ? "" : ", ");
    ms_strbuild_append(&text, names[i]);
  }
  return message(arena, error, &text);
}

/* `target` for alias `alias` naming `base`: a directory takes `/<file>.ms`, a file takes nothing. */
static bool alias_target(MsArena *arena, MsSpan alias, MsSpan base, MsSpan remainder, MsSpan *target,
                         MsProjectError *error) {
  MsStrBuild text = ms_strbuild_new();
  if (ms_dir_exists(base)) {
    if (remainder.len == 0 || !ms_span_is_text(ms_path_ext(remainder), ".ms")) {
      ms_strbuild_append_text(&text, "directory alias requires a .ms path; write \"");
      ms_strbuild_append(&text, alias);
      ms_strbuild_append_text(&text, "/<file>.ms\"");
      return message(arena, error, &text);
    }
    ms_path_append_joined(&text, base, remainder);
    MsStrBuild cleaned = ms_strbuild_new();
    ms_path_clean(&cleaned, ms_strbuild_span(&text));
    ms_strbuild_free(&text);
    *target = ms_project_text(arena, &cleaned);
    return true;
  }
  if (!ms_file_is_regular(base)) {
    ms_strbuild_free(&text);
    ms_project_error_path(error, "stat", base, OS_ENOENT);
    return false;
  }
  if (remainder.len != 0 || !ms_span_is_text(ms_path_ext(base), ".ms")) {
    ms_strbuild_append_text(&text, "file alias does not accept a suffix; alias ");
    ms_strbuild_append(&text, alias);
    ms_strbuild_append_text(&text, " names one file, so import it as \"");
    ms_strbuild_append(&text, alias);
    ms_strbuild_append_text(&text, "\" alone");
    return message(arena, error, &text);
  }
  ms_strbuild_free(&text);
  *target = base;
  return true;
}

static bool alias_import(MsArena *arena, const MsManifest *manifest, MsSpan path, MsSpan *target,
                         MsProjectError *error) {
  MsSpan alias = path;
  MsSpan remainder = {0};
  size_t slash = 0;
  if (ms_span_find(path, ms_span_of_text("/"), &slash)) {
    alias = ms_span_of(path.ptr, slash);
    remainder = ms_span_of(path.ptr + slash + 1, path.len - slash - 1);
  }
  MsSpan base = {0};
  if (manifest != NULL && ms_manifest_find(&manifest->embeds, alias, &base)) {
    if (remainder.len == 0) {
      *target = ms_project_embed_module_path(arena, manifest->root, alias);
      return true;
    }
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "embed ");
    ms_strbuild_append(&text, alias);
    ms_strbuild_append_text(&text, " names a generated module, so import it as \"");
    ms_strbuild_append(&text, alias);
    ms_strbuild_append_text(&text, "\" alone");
    return message(arena, error, &text);
  }
  if (manifest == NULL ||
      !(ms_manifest_find(&manifest->aliases, alias, &base) || ms_manifest_find(&manifest->deps, alias, &base))) {
    return unknown_alias(arena, manifest, alias, error);
  }
  return alias_target(arena, alias, base, remainder, target, error);
}

static bool bare_error(MsArena *arena, MsSpan path, MsProjectError *error) {
  const bool placeholder = path.len == 0 || ms_span_is_text(path, ".") || ms_span_is_text(path, "..");
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "imports require a relative path or alias; write \"./");
  ms_strbuild_append(&text, placeholder ? ms_span_of_text("name.ms") : path);
  ms_strbuild_append_text(&text, "\" for a file next to this one, \"@std/name.ms\" for the standard library, "
                                 "or declare an alias under [aliases] in ms.toml");
  return message(arena, error, &text);
}

bool ms_project_import_target(MsArena *arena, const MsManifest *manifest, MsSpan importer, MsSpan path,
                              MsSpan *target, MsProjectError *error) {
  size_t at = 0;
  if (ms_span_find(path, ms_span_of_text("\\"), &at)) {
    return fail_text(arena, error,
                     "import paths use / separators; write \"./dir/file.ms\" instead of backslashes");
  }
  if (ms_span_starts_with(path, ms_span_of_text("./")) || ms_span_starts_with(path, ms_span_of_text("../"))) {
    return relative_target(arena, importer, path, target, error);
  }
  if (ms_span_starts_with(path, ms_span_of_text("@"))) {
    return alias_import(arena, manifest, path, target, error);
  }
  if (ms_span_starts_with(path, ms_span_of_text("/"))) {
    return fail_text(arena, error,
                     "absolute import paths are not supported; write a relative path such as \"../name.ms\" "
                     "from this file, or declare an alias under [aliases] in ms.toml");
  }
  return bare_error(arena, path, error);
}

/* The first component of `path` that does not exist, as a prefix of it. */
static MsSpan missing_prefix(MsSpan path) {
  for (size_t end = 1; end <= path.len; end++) {
    if (end != path.len && path.ptr[end] != '/') {
      continue;
    }
    MsString real = ms_string_empty();
    const MsSpan prefix = ms_span_of(path.ptr, end);
    if (ms_file_real_path(prefix, &real)) {
      ms_string_release(&real);
      continue;
    }
    return prefix;
  }
  return path;
}

static void real_path_error(MsArena *arena, MsSpan path, int os_error, MsProjectError *error) {
  if (os_error == OS_ENOTDIR) {
    ms_project_error_path(error, "lstat", path, os_error);
    return;
  }
  const MsSpan named = os_error == OS_ENOENT ? missing_prefix(path) : path;
  ms_project_error_path(error, "lstat", ms_arena_copy(arena, named), os_error);
}

static bool overlay_has(const MsOverlay *overlay, MsSpan path) {
  for (size_t i = 0; overlay != NULL && i < overlay->count; i++) {
    if (ms_span_equal(overlay->files[i].path, path)) {
      return true;
    }
  }
  return false;
}

/* A file the overlay holds that is not on disk lies beneath an existing directory. */
static bool overlay_path(MsArena *arena, MsSpan path, const MsOverlay *overlay, MsSpan *canonical) {
  MsString parent = ms_string_empty();
  if (!ms_file_real_path(directory_of(path), &parent)) {
    return false;
  }
  MsStrBuild joined = ms_strbuild_new();
  ms_path_append_joined(&joined, ms_string_span(&parent), ms_path_file_name(path));
  ms_string_release(&parent);
  *canonical = ms_project_text(arena, &joined);
  return overlay_has(overlay, path) || overlay_has(overlay, *canonical);
}

static bool escapes_root(MsArena *arena, MsSpan root, MsSpan canonical, MsSpan path, MsProjectError *error) {
  MsStrBuild relative = ms_strbuild_new();
  const bool inside = ms_path_relative(&relative, root, canonical) && !ms_path_escapes(ms_strbuild_span(&relative));
  ms_strbuild_free(&relative);
  if (inside) {
    return false;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "path escapes project root: ");
  ms_strbuild_append(&text, path);
  ms_strbuild_append_text(&text, "; keep imported files inside the directory containing ms.toml (or the entry "
                                 "file's directory)");
  (void)message(arena, error, &text);
  return true;
}

bool ms_project_source_path(MsArena *arena, MsSpan root, MsSpan path, const MsOverlay *overlay,
                            MsSpan *canonical, MsProjectError *error) {
  MsStrBuild joined = ms_strbuild_new();
  if (ms_path_is_absolute(path)) {
    ms_strbuild_append(&joined, path);
  } else {
    ms_path_append_joined(&joined, root, path);
  }
  const MsSpan full = ms_project_text(arena, &joined);
  MsString real = ms_string_empty();
  if (ms_file_real_path(full, &real)) {
    *canonical = ms_arena_copy(arena, ms_string_span(&real));
    ms_string_release(&real);
  } else {
    const int os_error = errno;
    const bool absent = os_error == OS_ENOENT && overlay != NULL && overlay->count != 0;
    if (!absent || !overlay_path(arena, full, overlay, canonical)) {
      real_path_error(arena, full, os_error, error);
      return false;
    }
  }
  return !escapes_root(arena, root, *canonical, full, error);
}

static MsSpan relative_to_cwd(MsArena *arena, MsSpan path) {
  MsString cwd = ms_string_empty();
  if (!ms_dir_current(&cwd)) {
    return path;
  }
  MsStrBuild relative = ms_strbuild_new();
  const bool inside = ms_path_relative(&relative, ms_string_span(&cwd), path) &&
                      !ms_path_escapes(ms_strbuild_span(&relative));
  ms_string_release(&cwd);
  if (!inside) {
    ms_strbuild_free(&relative);
    return path;
  }
  return ms_project_text(arena, &relative);
}

MsSpan ms_project_explain(MsArena *arena, const MsProjectError *error, MsSpan import_path) {
  if (error->kind != MS_PERR_PATH) {
    return ms_project_error_text(arena, error);
  }
  const MsSpan name = relative_to_cwd(arena, error->path);
  MsStrBuild text = ms_strbuild_new();
  if (error->os_error == OS_ENOENT && import_path.len != 0) {
    ms_strbuild_append_text(&text, "cannot find module ");
    ms_strbuild_append(&text, import_path);
    ms_strbuild_append_text(&text, " (looked for ");
    ms_strbuild_append(&text, name);
    ms_strbuild_append_text(&text, "); check the spelling, make sure the file exists, and that the path is "
                                   "relative to the importing file");
  } else if (error->os_error == OS_ENOENT) {
    ms_strbuild_append_text(&text, "file not found: ");
    ms_strbuild_append(&text, name);
    ms_strbuild_append_text(&text, "; check the path, pass a .ms file or a project ms.toml, and run from the "
                                   "directory that contains it");
  } else if (error->os_error == OS_EACCES) {
    ms_strbuild_append_text(&text, "permission denied reading ");
    ms_strbuild_append(&text, name);
    ms_strbuild_append_text(&text, "; make the file readable");
  } else {
    ms_strbuild_free(&text);
    return ms_project_error_text(arena, error);
  }
  return ms_project_text(arena, &text);
}

/* The directory an import may not leave: the package holding `target` for an `@` import, otherwise the importer's own
 * project or package. */
static MsSpan confinement_root(const MsManifest *manifest, MsSpan root, MsSpan importer, MsSpan path, MsSpan target) {
  const MsPackage *own = ms_manifest_package_of(manifest, importer);
  const MsSpan own_root = own == NULL ? root : own->root;
  if (!ms_span_starts_with(path, ms_span_of_text("@"))) {
    return own_root;
  }
  const MsPackage *holder = ms_manifest_package_of(manifest, target);
  return holder == NULL ? own_root : holder->root;
}

bool ms_project_resolve_in(MsArena *arena, const MsManifest *manifest, MsSpan root, const MsOverlay *overlay,
                           MsSpan importer, MsSpan path, MsSpan *canonical, MsProjectError *error) {
  MsSpan target = {0};
  if (!ms_project_import_target(arena, ms_manifest_scope(manifest, importer), importer, path, &target, error)) {
    return false;
  }
  MsSpan name = {0};
  MsSpan directory = {0};
  if (ms_project_embed_of(arena, manifest, target, &name, &directory)) {
    *canonical = target; /* generated on load: no file exists to canonicalise */
    return true;
  }
  return ms_project_source_path(arena, confinement_root(manifest, root, importer, path, target), target, overlay,
                                canonical, error);
}

bool ms_project_resolve_import(MsArena *arena, MsSpan root, const MsOverlay *overlay, MsSpan importer,
                               MsSpan path, MsSpan *canonical, MsProjectError *error) {
  return ms_project_resolve_in(arena, NULL, root, overlay, importer, path, canonical, error);
}

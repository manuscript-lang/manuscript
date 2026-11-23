/* Owns the three package commands of package_commands.h: finding the project, installing into the lock, and editing
 * the manifest around it. */
#include "cli/files.h"
#include "cli/package_commands.h"

#include <stdio.h>

#include "base/arena.h"
#include "base/bytes.h"
#include "base/dir.h"
#include "base/file.h"
#include "base/message.h"
#include "base/path.h"
#include "compiler/project/edit.h"
#include "compiler/project/lock.h"
#include "compiler/project/project.h"
#include "compiler/project/semver.h"
#include "compiler/project/solve.h"
#include "compiler/project/workspace.h"
#include "cli/package_fetch.h"

MS_LIST_DEFINE(SpanList, span_list, MsSpan)
MS_LIST_DEFINE(RootList, root_list, MsRoot)

static void print(FILE *stream, MsSpan text) {
  (void)fwrite(text.ptr, 1, text.len, stream);
}

static int report_status(const char *command, MsSpan message, int status) {
  (void)fprintf(stderr, "ms %s: ", command);
  print(stderr, message);
  (void)fputc('\n', stderr);
  return status;
}

static int report(const char *command, MsSpan message) {
  return report_status(command, message, 1);
}

/* An option the command does not have is a usage error, like every other command's: status 2. */
static int report_unknown_option(const char *command, MsArena *arena, MsSpan option) {
  return report_status(command,
                       ms_message_format(arena, "unknown option %S; run 'ms help %s' for its options", option, command),
                       2);
}

/* `path` made absolute against the working directory. */
static MsSpan absolute(MsArena *arena, MsSpan path) {
  MsString here = ms_string_empty();
  if (ms_path_is_absolute(path) || !ms_dir_current(&here)) {
    return path;
  }
  const MsSpan full = ms_cli_joined(arena, ms_string_span(&here), path);
  ms_string_release(&here);
  return full;
}

/* The nearest ms.toml from the working directory; false when there is none. */
static bool find_project(MsArena *arena, MsSpan *manifest) {
  MsString here = ms_string_empty();
  if (!ms_dir_current(&here)) {
    return false;
  }
  MsSpan directory = ms_arena_copy(arena, ms_string_span(&here));
  ms_string_release(&here);
  for (;;) {
    const MsSpan candidate = ms_cli_joined(arena, directory, ms_span_of_text("ms.toml"));
    if (ms_path_kind(candidate) != MS_PATH_MISSING) {
      *manifest = candidate;
      return true;
    }
    const MsSpan parent = ms_path_parent(directory);
    if (parent.len == 0 || ms_span_equal(parent, directory)) {
      return false;
    }
    directory = parent;
  }
}

#define NO_PROJECT "no ms.toml here or above; run `ms init` first"

/* ---- install ---- */

typedef struct Install {
  MsArena *arena;
  MsGitRemote remote;
  bool opened;
  MsResolved resolved;
} Install;

static bool write_lock(Install *in, MsSpan lock_root, const MsResolved *resolved, MsSpan *error) {
  const MsSpan path = ms_cli_joined(in->arena, lock_root, ms_span_of_text("ms.lock"));
  if (resolved->ncopies == 0) {
    ms_path_remove(path);
    return true;
  }
  MsLockEntry *entries = MS_ARENA_NEW_ARRAY(in->arena, MsLockEntry, resolved->ncopies);
  for (size_t i = 0; i < resolved->ncopies; i++) {
    entries[i] = resolved->copies[i].entry;
  }
  const MsSpan text = ms_lock_text(in->arena, entries, resolved->ncopies);
  MsBytes current = {0};
  const bool same = ms_file_read(path, &current) && ms_span_equal(ms_bytes_span(&current), text);
  ms_bytes_free(&current);
  if (!same && !ms_file_write(path, text)) {
    *error = ms_message_format(in->arena, "cannot write %S; check that it is writable", path);
    return false;
  }
  return true;
}

static const MsCopy *copy_named(const MsResolved *resolved, MsSpan id) {
  for (size_t i = 0; i < resolved->ncopies; i++) {
    if (ms_span_equal(resolved->copies[i].id, id)) {
      return &resolved->copies[i];
    }
  }
  return NULL;
}

static MsSpan alias_of(const MsResolved *resolved, MsSpan id) {
  for (size_t i = 0; i < resolved->nroots; i++) {
    if (ms_span_equal(resolved->roots[i].id, id)) {
      return resolved->roots[i].alias;
    }
  }
  return id;
}

static void print_copies(Install *in, const MsResolved *resolved) {
  for (size_t i = 0; i < resolved->ncopies; i++) {
    const MsCopy *copy = &resolved->copies[i];
    MsStrBuild effects = ms_strbuild_new();
    for (size_t j = 0; j < copy->manifest->neffects; j++) {
      ms_strbuild_append_text(&effects, j == 0 ? "" : " ");
      ms_strbuild_append(&effects, copy->manifest->effects[j]);
    }
    const MsSpan listed = copy->manifest->neffects == 0 ? ms_span_of_text("none") : ms_strbuild_span(&effects);
    const MsSpan revision = ms_span_of(copy->entry.revision.ptr, copy->entry.revision.len < 12 ? copy->entry.revision.len : 12);
    print(stdout, ms_message_format(in->arena, "%S %S %S (effects: %S)\n", alias_of(resolved, copy->id),
                                    copy->entry.spec, revision, listed));
    ms_strbuild_free(&effects);
  }
}

/* The roots of a manifest: itself, or every member of the workspace that holds it. Sets `*lock_root`. */
static bool read_roots(Install *in, MsSpan manifest, RootList *roots, MsSpan *lock_root, MsSpan *error) {
  MsArena *arena = in->arena;
  MsManifest *project = MS_ARENA_NEW(arena, MsManifest);
  MsProjectError problem = {0};
  if (!ms_manifest_read(arena, manifest, project, &problem)) {
    *error = ms_project_error_text(arena, &problem);
    return false;
  }
  MsWorkspace workspace = {0};
  bool found = false;
  if (!ms_workspace_find(arena, manifest, &workspace, &found, &problem)) {
    *error = ms_project_error_text(arena, &problem);
    return false;
  }
  if (!found) {
    *lock_root = project->root;
    root_list_push(roots, (MsRoot){.name = ms_span_of_text("the project"), .manifest = project});
    return true;
  }
  *lock_root = workspace.root;
  for (size_t i = 0; i < workspace.members.len; i++) {
    MsManifest *member = MS_ARENA_NEW(arena, MsManifest);
    if (!ms_manifest_read(arena, ms_workspace_manifest(arena, &workspace.members.ptr[i]), member, &problem)) {
      *error = ms_project_error_text(arena, &problem);
      return false;
    }
    root_list_push(roots, (MsRoot){.name = workspace.members.ptr[i].name, .manifest = member});
  }
  return true;
}

static bool install_manifest(Install *in, MsSpan manifest, const SpanList *update, MsSpan *error) {
  RootList roots = {0};
  MsSpan lock_root = {0};
  MsLockList old = {0};
  bool ok = read_roots(in, manifest, &roots, &lock_root, error) && ms_lock_read(in->arena, lock_root, &old, error);
  if (ok && !in->opened) {
    ok = ms_git_remote_open(&in->remote, in->arena, error);
    in->opened = ok;
  }
  if (ok) {
    const MsResolveRequest request = {.roots = roots.ptr, .nroots = roots.len, .old = old.ptr, .nold = old.len,
                                      .update = update->ptr, .nupdate = update->len,
                                      .remote = &in->remote.remote};
    ok = ms_resolve(in->arena, &request, &in->resolved, error) && write_lock(in, lock_root, &in->resolved, error);
  }
  if (ok) {
    print_copies(in, &in->resolved);
  }
  root_list_free(&roots);
  ms_lock_list_free(&old);
  return ok;
}

static void finish_install(Install *in) {
  if (in->opened) {
    ms_git_remote_close(&in->remote);
  }
}

int ms_install_command(int argc, char **argv) {
  MsArena arena = ms_arena_new();
  Install in = {.arena = &arena};
  SpanList update = {0};
  MsSpan manifest = {0};
  int status = 0;
  for (int i = 0; i < argc && status == 0; i++) {
    const MsSpan arg = ms_span_of_text(argv[i]);
    if (ms_span_is_text(arg, "--update")) {
      if (i + 1 >= argc) {
        status = report("install", ms_span_of_text("--update needs a package name such as @pg"));
      } else {
        span_list_push(&update, ms_span_of_text(argv[++i]));
      }
    } else if (arg.len > 0 && arg.ptr[0] == '-') {
      status = report_unknown_option("install", &arena, arg);
    } else {
      manifest = absolute(&arena, arg);
    }
  }
  MsSpan error = {0};
  if (status == 0 && manifest.len == 0 && !find_project(&arena, &manifest)) {
    status = report("install", ms_span_of_text(NO_PROJECT));
  }
  if (status == 0 && !install_manifest(&in, manifest, &update, &error)) {
    status = report("install", error);
  }
  finish_install(&in);
  span_list_free(&update);
  ms_arena_free(&arena);
  return status;
}

/* ---- add and remove ---- */

/* The text of the manifest, or an error. */
static bool read_text(MsArena *arena, MsSpan path, MsSpan *text, MsSpan *error) {
  MsBytes bytes = {0};
  if (!ms_file_read(path, &bytes)) {
    *error = ms_message_format(arena, "cannot read %S; check that it exists and is readable", path);
    return false;
  }
  *text = ms_arena_copy(arena, ms_bytes_span(&bytes));
  ms_bytes_free(&bytes);
  return true;
}

static bool write_text(MsArena *arena, MsSpan path, MsSpan text, MsSpan *error) {
  if (!ms_file_write(path, text)) {
    *error = ms_message_format(arena, "cannot write %S; check that it is writable", path);
    return false;
  }
  return true;
}

/* `ms add` and `ms remove` edit one project's `[dependencies]`, so they refuse a workspace root that has no
 * `[project]` of its own. */
static bool not_a_workspace_root(MsArena *arena, MsSpan manifest, const char *command, MsSpan *error) {
  MsManifest project = {0};
  MsProjectError problem = {0};
  if (ms_manifest_read(arena, manifest, &project, &problem) && project.is_workspace && project.name.len == 0) {
    *error = ms_message_format(arena, "%S is a workspace root; run ms %s inside a member directory", manifest, command);
    return false;
  }
  return true;
}

typedef struct AddOptions {
  MsSpan url, pin, name;
  MsSourceKind kind;
  bool has_pin, allow;
  bool usage; /* the error is an unknown option */
} AddOptions;

static bool take_value(MsArena *arena, int argc, char **argv, int *i, const char *what, MsSpan *value, MsSpan *error) {
  if (*i + 1 >= argc) {
    *error = ms_message_format(arena, "%s needs %s", argv[*i], what);
    return false;
  }
  *value = ms_span_of_text(argv[++*i]);
  return true;
}

static bool set_pin(MsArena *arena, int argc, char **argv, int *i, AddOptions *o, MsSpan *error) {
  const MsSpan flag = ms_span_of_text(argv[*i]);
  if (o->has_pin) {
    *error = ms_span_of_text("name exactly one of --version, --tag and --sha");
    return false;
  }
  const bool version = ms_span_is_text(flag, "--version");
  const bool tag = ms_span_is_text(flag, "--tag");
  const char *what = version ? "a requirement such as 1.2" : tag ? "a tag" : "a full commit";
  o->kind = version ? MS_SOURCE_VERSION : tag ? MS_SOURCE_TAG : MS_SOURCE_SHA;
  o->has_pin = take_value(arena, argc, argv, i, what, &o->pin, error);
  return o->has_pin;
}

static bool parse_add(MsArena *arena, int argc, char **argv, AddOptions *o, MsSpan *error) {
  for (int i = 0; i < argc; i++) {
    const MsSpan arg = ms_span_of_text(argv[i]);
    bool ok = true;
    if (ms_span_is_text(arg, "--version") || ms_span_is_text(arg, "--tag") || ms_span_is_text(arg, "--sha")) {
      ok = set_pin(arena, argc, argv, &i, o, error);
    } else if (ms_span_is_text(arg, "--as")) {
      ok = take_value(arena, argc, argv, &i, "a package name such as @pg", &o->name, error);
    } else if (ms_span_is_text(arg, "--allow")) {
      o->allow = true;
    } else if (arg.len > 0 && arg.ptr[0] == '-') {
      *error = ms_message_format(arena, "unknown option %S; run 'ms help add' for its options", arg);
      o->usage = true;
      ok = false;
    } else if (o->url.len == 0) {
      o->url = arg;
    } else {
      *error = ms_span_of_text("one repository URL at a time");
      ok = false;
    }
    if (!ok) {
      return false;
    }
  }
  if (o->url.len == 0) {
    *error = ms_span_of_text("name a repository URL: ms add <url> --version <requirement>");
  } else if (!o->has_pin) {
    *error = ms_span_of_text("name the version: --version <requirement>, --tag <tag> or --sha <full commit>");
  } else if (o->name.len == 0 && !ms_edit_default_name(arena, o->url, &o->name)) {
    *error = ms_message_format(arena, "cannot make a package name from %S; give one with --as @name", o->url);
  } else {
    return true;
  }
  return false;
}

/* The effects the dependency `name` declares, or none. */
static const MsManifest *declared_by(const MsResolved *resolved, MsSpan name) {
  for (size_t i = 0; i < resolved->nroots; i++) {
    if (ms_span_equal(resolved->roots[i].alias, name)) {
      const MsCopy *copy = copy_named(resolved, resolved->roots[i].id);
      return copy == NULL ? NULL : copy->manifest;
    }
  }
  return NULL;
}


static MsSpan quoted_list(MsArena *arena, const MsSpan *items, size_t count) {
  MsStrBuild text = ms_strbuild_new();
  for (size_t i = 0; i < count; i++) {
    ms_strbuild_printf(&text, "%s\"", i == 0 ? "" : ", ");
    ms_strbuild_append(&text, items[i]);
    ms_strbuild_append_byte(&text, '"');
  }
  const MsSpan copy = ms_message_from_builder(arena, &text);
  ms_strbuild_free(&text);
  return copy;
}

/* After a successful install: allow the effects the new dependency declares, or say how to. */
static bool handle_effects(Install *in, const AddOptions *o, MsSpan manifest_path, MsSpan edited, MsSpan *error) {
  const MsManifest *declared = declared_by(&in->resolved, o->name);
  if (declared == NULL || declared->neffects == 0) {
    return true;
  }
  const MsSpan list = quoted_list(in->arena, declared->effects, declared->neffects);
  if (!o->allow) {
    print(stdout, ms_message_format(in->arena,
                                    "%S declares effects. Allow them to build: add to [effects]\n  \"%S\" = [%S]\n"
                                    "or run `ms add --allow` next time.\n",
                                    o->name, o->name, list));
    return true;
  }
  MsSpan allowed = {0};
  if (!ms_edit_allow_effects(in->arena, edited, o->name, declared->effects, declared->neffects, &allowed, error) ||
      !write_text(in->arena, manifest_path, allowed, error)) {
    return false;
  }
  MsStrBuild names = ms_strbuild_new();
  for (size_t i = 0; i < declared->neffects; i++) {
    ms_strbuild_append_text(&names, i == 0 ? "" : " ");
    ms_strbuild_append(&names, declared->effects[i]);
  }
  print(stdout, ms_message_format(in->arena, "%S is allowed %S\n", o->name, ms_strbuild_span(&names)));
  ms_strbuild_free(&names);
  return true;
}

static bool pin_valid(MsArena *arena, const AddOptions *o, MsSpan *error) {
  MsRequirement requirement = {0};
  return o->kind != MS_SOURCE_VERSION || ms_requirement_parse(arena, o->pin, &requirement, error);
}

static bool add_dependency(Install *in, const AddOptions *o, MsSpan *error) {
  MsArena *arena = in->arena;
  MsSpan manifest = {0};
  MsSpan original = {0};
  MsSpan edited = {0};
  const SpanList none = {0};
  if (!find_project(arena, &manifest)) {
    *error = ms_span_of_text(NO_PROJECT);
    return false;
  }
  const MsDependencyEdit edit = {.name = o->name, .url = o->url, .kind = o->kind, .pin = o->pin};
  if (!not_a_workspace_root(arena, manifest, "add", error) || !read_text(arena, manifest, &original, error) ||
      !pin_valid(arena, o, error) || !ms_edit_add_dependency(arena, original, &edit, &edited, error) ||
      !write_text(arena, manifest, edited, error)) {
    return false;
  }
  if (!install_manifest(in, manifest, &none, error)) {
    MsSpan ignored = {0};
    (void)write_text(arena, manifest, original, &ignored); /* a dependency that cannot be installed is not left in */
    return false;
  }
  return handle_effects(in, o, manifest, edited, error);
}

int ms_add_command(int argc, char **argv) {
  MsArena arena = ms_arena_new();
  Install in = {.arena = &arena};
  AddOptions options = {0};
  MsSpan error = {0};
  int status = 0;
  if (!parse_add(&arena, argc, argv, &options, &error) || !add_dependency(&in, &options, &error)) {
    status = report_status("add", error, options.usage ? 2 : 1);
  }
  finish_install(&in);
  ms_arena_free(&arena);
  return status;
}

static bool remove_dependency(Install *in, MsSpan name, MsSpan *error) {
  MsArena *arena = in->arena;
  MsSpan manifest = {0};
  MsSpan original = {0};
  MsSpan edited = {0};
  const SpanList none = {0};
  if (!find_project(arena, &manifest)) {
    *error = ms_span_of_text(NO_PROJECT);
    return false;
  }
  if (!not_a_workspace_root(arena, manifest, "remove", error) || !read_text(arena, manifest, &original, error) ||
      !ms_edit_remove_dependency(arena, original, name, &edited, error) ||
      !write_text(arena, manifest, edited, error)) {
    return false;
  }
  if (!install_manifest(in, manifest, &none, error)) {
    MsSpan ignored = {0};
    (void)write_text(arena, manifest, original, &ignored);
    return false;
  }
  print(stdout, ms_message_format(arena, "removed %S\n", name));
  return true;
}

int ms_remove_command(int argc, char **argv) {
  MsArena arena = ms_arena_new();
  Install in = {.arena = &arena};
  MsSpan error = {0};
  int status = 0;
  if (argc > 0 && argv[0][0] == '-') {
    status = report_unknown_option("remove", &arena, ms_span_of_text(argv[0]));
  } else if (argc != 1) {
    status = report("remove", ms_span_of_text("name one package: ms remove @name"));
  } else if (!remove_dependency(&in, ms_span_of_text(argv[0]), &error)) {
    status = report("remove", error);
  }
  finish_install(&in);
  ms_arena_free(&arena);
  return status;
}

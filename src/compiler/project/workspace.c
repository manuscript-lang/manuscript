/* compiler/project/workspace.c: workspaces: the members a root `ms.toml` names. */
#include "compiler/project/workspace.h"

#include <errno.h>

#include "base/dir.h"
#include "base/file.h"
#include "base/message.h"
#include "base/path.h"
#include "base/sort.h"
#include "base/string.h"
#include "compiler/project/project_internal.h"

static bool fail_message(MsProjectError *error, MsSpan message) {
  ms_project_error_message(error, message);
  return false;
}

/* The canonical form of `path`; false with the cause in `error`. */
static bool canonical(MsArena *arena, MsSpan path, MsSpan *out, MsProjectError *error) {
  MsString real = ms_string_empty();
  if (!ms_file_real_path(path, &real)) {
    ms_project_error_path(error, "lstat", path, errno);
    return false;
  }
  *out = ms_arena_copy(arena, ms_string_span(&real));
  ms_string_release(&real);
  return true;
}

static MsSpan joined(MsArena *arena, MsSpan base, MsSpan name) {
  MsStrBuild path = ms_strbuild_new();
  ms_path_append_joined(&path, base, name);
  return ms_message_take_builder(arena, &path);
}

/* Whether `dir` is `root` or below it. */
static bool within(MsSpan root, MsSpan dir) {
  if (!ms_span_starts_with(dir, root)) {
    return false;
  }
  return dir.len == root.len || dir.ptr[root.len] == '/' || (root.len != 0 && root.ptr[root.len - 1] == '/');
}

/* `dir` relative to `root`, or `dir` itself for the root. */
static MsSpan relative_or(MsArena *arena, MsSpan root, MsSpan dir) {
  MsStrBuild relative = ms_strbuild_new();
  if (!ms_path_relative(&relative, root, dir) || ms_span_is_text(ms_strbuild_span(&relative), ".")) {
    ms_strbuild_free(&relative);
    return dir;
  }
  return ms_message_take_builder(arena, &relative);
}

static bool member_error(MsArena *arena, MsProjectError *error, MsSpan pattern, const char *why) {
  return fail_message(error, ms_message_format(arena,
                                               "workspace member %S %s; write a directory below the workspace root "
                                               "such as \"app\" or \"libs/*\"",
                                               ms_project_quote(arena, pattern), why));
}

static int64_t compare_paths(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const MsSpan x = *(const MsSpan *)(const void *)a;
  const MsSpan y = *(const MsSpan *)(const void *)b;
  const size_t common = x.len < y.len ? x.len : y.len;
  const int order = common == 0 ? 0 : __builtin_memcmp(x.ptr, y.ptr, common);
  if (order != 0) {
    return order < 0 ? -1 : 1;
  }
  return x.len < y.len ? -1 : x.len > y.len;
}

/* The child directories of `parent` holding an ms.toml, canonical, sorted; hidden ones are never members. */
static bool wildcard_members(MsArena *arena, MsSpan root, MsSpan parent, MsSpanList *dirs, MsProjectError *error) {
  MsDirEntryList entries = {0};
  if (!ms_dir_list(parent, &entries)) {
    ms_project_error_path(error, "read directory", parent, errno);
    return false;
  }
  MsSpanList children = {0};
  for (size_t i = 0; i < entries.len; i++) {
    const MsSpan name = ms_string_span(&entries.ptr[i].name);
    const MsSpan path = joined(arena, parent, name);
    MsSpan real = {0};
    if (name.len == 0 || name.ptr[0] == '.' || !ms_file_is_regular(joined(arena, path, ms_span_of_text("ms.toml")))) {
      continue;
    }
    if (!canonical(arena, path, &real, error)) {
      ms_span_list_free(&children);
      ms_dir_entries_free(&entries);
      return false;
    }
    if (within(root, real)) {
      ms_span_list_push(&children, real);
    }
  }
  ms_dir_entries_free(&entries);
  if (children.len > 1) {
    ms_sort((uint8_t *)children.ptr, children.len, sizeof(MsSpan), compare_paths, NULL);
  }
  for (size_t i = 0; i < children.len; i++) {
    ms_span_list_push(dirs, children.ptr[i]);
  }
  ms_span_list_free(&children);
  return true;
}

/* The directories one member pattern names, appended to `dirs`. */
static bool expand_member(MsArena *arena, MsSpan root, MsSpan pattern, MsSpanList *dirs, MsProjectError *error) {
  const bool wildcard = ms_span_ends_with(pattern, ms_span_of_text("/*"));
  const MsSpan base = wildcard ? ms_span_of(pattern.ptr, pattern.len - 2) : pattern;
  bool star = false;
  for (size_t i = 0; i < base.len; i++) {
    star = star || base.ptr[i] == '*';
  }
  if (base.len == 0 || ms_path_is_absolute(base) || ms_path_escapes(base) || star) {
    return member_error(arena, error, pattern, "is not a relative directory inside the workspace");
  }
  MsSpan parent = {0};
  MsProjectError unused = {0};
  if (!canonical(arena, joined(arena, root, base), &parent, &unused)) {
    return member_error(arena, error, pattern, "does not exist");
  }
  if (!within(root, parent)) {
    return member_error(arena, error, pattern, "leaves the workspace root");
  }
  if (!wildcard) {
    ms_span_list_push(dirs, parent);
    return true;
  }
  return wildcard_members(arena, root, parent, dirs, error);
}

static bool listed(const WorkspaceMemberList *members, MsSpan dir) {
  for (size_t i = 0; i < members->len; i++) {
    if (ms_span_equal(members->ptr[i].root, dir)) {
      return true;
    }
  }
  return false;
}

/* Reads one member's manifest and checks what a member must be. */
static bool read_member(MsArena *arena, MsSpan root, MsSpan dir, const WorkspaceMemberList *seen, MsManifest *project,
                        MsProjectError *error) {
  MsProjectError cause = {0};
  const MsSpan shown = relative_or(arena, root, dir);
  if (!ms_manifest_read(arena, joined(arena, dir, ms_span_of_text("ms.toml")), project, &cause)) {
    return fail_message(error, ms_message_format(arena, "workspace member %S: %S", shown,
                                                 ms_project_error_text(arena, &cause)));
  }
  if (!ms_span_equal(dir, root) && ms_file_is_regular(joined(arena, dir, ms_span_of_text("ms.lock")))) {
    return fail_message(error, ms_message_format(arena,
                                                 "workspace member %S has its own ms.lock, which is never read; the "
                                                 "workspace keeps one ms.lock at %S, so delete the member's",
                                                 shown, root));
  }
  if (project->name.len == 0) {
    return fail_message(error, ms_message_format(arena,
                                                 "workspace member %S has no [project]; a member is a project with a "
                                                 "name and source",
                                                 shown));
  }
  for (size_t i = 0; i < seen->len; i++) {
    if (ms_span_equal(seen->ptr[i].name, project->name)) {
      return fail_message(error, ms_message_format(arena,
                                                   "workspace members %S and %S are both named %S; rename one in "
                                                   "[project]",
                                                   relative_or(arena, root, seen->ptr[i].root), shown,
                                                   ms_project_quote(arena, project->name)));
    }
  }
  return true;
}

bool ms_workspace_read(MsArena *arena, const MsManifest *root_project, MsWorkspace *out, MsProjectError *error) {
  *out = (MsWorkspace){.root = root_project->root};
  MsSpanList dirs = {0};
  /* The root's own project, when it has one, is a member. */
  if (root_project->name.len != 0) {
    ms_span_list_push(&dirs, root_project->root);
  }
  for (size_t i = 0; i < root_project->members.len; i++) {
    if (!expand_member(arena, root_project->root, root_project->members.ptr[i], &dirs, error)) {
      ms_span_list_free(&dirs);
      return false;
    }
  }
  if (dirs.len == 0) {
    ms_span_list_free(&dirs);
    return fail_message(error, ms_span_of_text("workspace lists no members; name each member directory under "
                                               "[workspace], such as members = [\"app\", \"libs/*\"]"));
  }
  bool ok = true;
  for (size_t i = 0; i < dirs.len && ok; i++) {
    if (listed(&out->members, dirs.ptr[i])) {
      continue;
    }
    MsManifest project = {0};
    ok = read_member(arena, root_project->root, dirs.ptr[i], &out->members, &project, error);
    if (ok) {
      workspace_member_list_push(&out->members, (MsWorkspaceMember){.name = project.name, .root = dirs.ptr[i]});
    }
    ms_manifest_free(&project);
  }
  ms_span_list_free(&dirs);
  return ok;
}

const MsWorkspaceMember *ms_workspace_member_at(const MsWorkspace *workspace, MsSpan dir) {
  for (size_t i = 0; i < workspace->members.len; i++) {
    if (ms_span_equal(workspace->members.ptr[i].root, dir)) {
      return &workspace->members.ptr[i];
    }
  }
  return NULL;
}

MsSpan ms_workspace_manifest(MsArena *arena, const MsWorkspaceMember *member) {
  return joined(arena, member->root, ms_span_of_text("ms.toml"));
}

void ms_workspace_free(MsWorkspace *workspace) {
  workspace_member_list_free(&workspace->members);
}

bool ms_workspace_find(MsArena *arena, MsSpan manifest, MsWorkspace *out, bool *found, MsProjectError *error) {
  *found = false;
  MsSpan here = {0};
  if (!canonical(arena, ms_path_parent(manifest), &here, error)) {
    return false;
  }
  for (MsSpan dir = here;;) {
    const MsSpan candidate = joined(arena, dir, ms_span_of_text("ms.toml"));
    MsManifest root = {0};
    MsProjectError unused = {0};
    /* A broken or unrelated ancestor manifest is not a workspace; its own errors surface when it is the project. */
    if (ms_file_is_regular(candidate) && ms_manifest_read(arena, candidate, &root, &unused) && root.is_workspace) {
      MsWorkspace workspace = {0};
      const bool ok = ms_workspace_read(arena, &root, &workspace, error);
      const bool mine = ok && (ms_span_equal(dir, here) || ms_workspace_member_at(&workspace, here) != NULL);
      ms_manifest_free(&root);
      if (!ok || !mine) {
        ms_workspace_free(&workspace);
        return ok;
      }
      *out = workspace;
      *found = true;
      return true;
    }
    ms_manifest_free(&root);
    const MsSpan parent = ms_path_parent(dir);
    if (parent.len == 0 || parent.len == dir.len) {
      return true;
    }
    dir = parent;
  }
}

bool ms_workspace_root_members(MsArena *arena, MsSpan manifest, MsWorkspace *out, bool *found, MsProjectError *error) {
  *found = false;
  if (!ms_span_is_text(ms_path_file_name(manifest), "ms.toml") || !ms_file_is_regular(manifest)) {
    return true;
  }
  MsManifest root = {0};
  MsProjectError unused = {0};
  /* A manifest that does not parse is reported by the command itself, in its own format. */
  const bool readable = ms_manifest_read(arena, manifest, &root, &unused);
  const bool only_members = readable && root.is_workspace && root.name.len == 0;
  const bool ok = !only_members || ms_workspace_read(arena, &root, out, error);
  *found = only_members && ok;
  ms_manifest_free(&root);
  return ok;
}

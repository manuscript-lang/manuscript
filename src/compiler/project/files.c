/* compiler/project/files.c: the source files a command's target stands for (`ms fmt`): a .ms file is itself;
 * a directory or an ms.toml stands for the project's modules, as `format_paths` in crates/ms-cli/src/fmt.rs. */
#include <errno.h>

#include "base/file.h"
#include "base/path.h"
#include "compiler/project/manifest.h"
#include "compiler/project/workspace.h"

static bool stat_failure(MsArena *arena, MsSpan target, MsProjectError *error) {
  MsString real = ms_string_empty();
  const bool exists = ms_file_real_path(target, &real);
  const int os_error = exists ? 0 : errno;
  ms_string_release(&real);
  ms_project_error_path(error, "stat", ms_arena_copy(arena, target), os_error);
  return false;
}

static bool absolute_target(MsArena *arena, MsSpan target, MsSpan *absolute, MsProjectError *error) {
  MsStrBuild joined = ms_strbuild_new();
  if (ms_path_is_absolute(target)) {
    ms_strbuild_append(&joined, target);
  } else {
    MsString cwd = ms_string_empty();
    if (!ms_dir_current(&cwd)) {
      ms_strbuild_free(&joined);
      ms_project_error_path(error, "getwd", ms_span_of_text("."), errno);
      return false;
    }
    ms_path_append_joined(&joined, ms_string_span(&cwd), target);
    ms_string_release(&cwd);
  }
  MsStrBuild cleaned = ms_strbuild_new();
  ms_path_clean(&cleaned, ms_strbuild_span(&joined));
  ms_strbuild_free(&joined);
  *absolute = ms_project_text(arena, &cleaned);
  return true;
}

/* Confines each found path to `root`: a discovered link must stay inside the selected project. */
static bool confine(MsArena *arena, MsSpan root, const MsSpanList *found, MsSpanList *paths,
                    MsProjectError *error) {
  for (size_t i = 0; i < found->len; i++) {
    MsSpan canonical = {0};
    if (!ms_project_source_path(arena, root, found->ptr[i], NULL, &canonical, error)) {
      return false;
    }
    ms_span_list_push(paths, canonical);
  }
  return true;
}

bool ms_project_format_files(MsArena *arena, MsSpan target, MsSpanList *paths, MsProjectError *error) {
  const bool directory = ms_dir_exists(target);
  const bool manifest = ms_span_is_text(ms_path_file_name(target), "ms.toml");
  if (!directory && !ms_file_is_regular(target) && !manifest) {
    return stat_failure(arena, target, error);
  }
  if (!directory && !manifest) {
    ms_span_list_push(paths, ms_arena_copy(arena, target));
    return true;
  }
  MsSpan absolute = {0};
  MsManifest config = {0};
  MsSpan root = {0};
  MsSpan source = {0};
  MsSpan entry = {0};
  if (!absolute_target(arena, target, &absolute, error)) {
    return false;
  }
  MsString real = ms_string_empty();
  if (directory) {
    if (!ms_file_real_path(absolute, &real)) {
      ms_project_error_path(error, "lstat", absolute, errno);
      return false;
    }
    root = ms_arena_copy(arena, ms_string_span(&real));
    ms_string_release(&real);
    source = root;
  } else {
    if (!ms_manifest_read(arena, absolute, &config, error)) {
      ms_manifest_free(&config);
      return false;
    }
    root = config.root;
    source = config.source;
    entry = config.entry;
    ms_manifest_free(&config);
  }
  MsSpanList found = {0};
  bool ok = ms_project_discover(arena, root, source, true, &found, error);
  if (ok && entry.len != 0) {
    ms_span_list_push(&found, entry);
  }
  ok = ok && confine(arena, root, &found, paths, error);
  ms_span_list_free(&found);
  return ok;
}

bool ms_project_workspace_members(MsArena *arena, MsSpan target, MsSpanList *manifests, bool *found,
                                  MsProjectError *error) {
  *found = false;
  MsSpan absolute = {0};
  if (!ms_span_is_text(ms_path_file_name(target), "ms.toml") || !ms_file_is_regular(target)) {
    return true;
  }
  if (!absolute_target(arena, target, &absolute, error)) {
    return false;
  }
  MsWorkspace workspace = {0};
  if (!ms_workspace_root_members(arena, absolute, &workspace, found, error)) {
    return false;
  }
  for (size_t i = 0; *found && i < workspace.members.len; i++) {
    ms_span_list_push(manifests, ms_workspace_manifest(arena, &workspace.members.ptr[i]));
  }
  ms_workspace_free(&workspace);
  return true;
}

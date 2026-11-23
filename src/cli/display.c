/* Owns the path display helpers of display.h. */
#include "cli/display.h"

#include "base/file.h"
#include "base/path.h"

/* The text of `builder` copied into `arena`; the builder is freed. */
static MsSpan arena_text(MsArena *arena, MsStrBuild *builder) {
  const MsSpan text = ms_arena_copy(arena, ms_strbuild_span(builder));
  ms_strbuild_free(builder);
  return text;
}

/* The canonical absolute spelling of `path`, or false. */
bool ms_display_physical(MsArena *arena, MsSpan path, MsSpan *out) {
  MsStrBuild joined = ms_strbuild_new();
  if (ms_path_is_absolute(path)) {
    ms_strbuild_append(&joined, path);
  } else {
    MsString cwd = ms_string_empty();
    if (!ms_dir_current(&cwd)) {
      ms_strbuild_free(&joined);
      return false;
    }
    ms_path_append_joined(&joined, ms_string_span(&cwd), path);
    ms_string_release(&cwd);
  }
  MsString real = ms_string_empty();
  const bool ok = ms_file_real_path(ms_strbuild_span(&joined), &real);
  ms_strbuild_free(&joined);
  if (ok) {
    *out = ms_arena_copy(arena, ms_string_span(&real));
    ms_string_release(&real);
  }
  return ok;
}

/* `path` as shown: relative to the working directory when it lies below it, else absolute. */
MsSpan ms_display_of(MsArena *arena, MsSpan path) {
  MsSpan absolute = path;
  MsString cwd = ms_string_empty();
  MsSpan real_cwd = {0};
  if (!ms_dir_current(&cwd) || !ms_display_physical(arena, ms_string_span(&cwd), &real_cwd)) {
    ms_string_release(&cwd);
    return path;
  }
  ms_string_release(&cwd);
  (void)ms_display_physical(arena, path, &absolute);
  MsStrBuild relative = ms_strbuild_new();
  if (!ms_path_relative(&relative, real_cwd, absolute) || ms_path_escapes(ms_strbuild_span(&relative))) {
    ms_strbuild_free(&relative);
    return absolute;
  }
  if (relative.bytes.len > 0 && relative.bytes.ptr[0] == '-') {
    MsStrBuild dotted = ms_strbuild_new();
    ms_strbuild_append_text(&dotted, "./");
    ms_strbuild_append(&dotted, ms_strbuild_span(&relative));
    ms_strbuild_free(&relative);
    return arena_text(arena, &dotted);
  }
  return arena_text(arena, &relative);
}

MsSpan ms_display_path_message(MsArena *arena, const MsProjectError *error, MsSpan shown) {
  MsProjectError named = *error;
  named.path = shown;
  MsStrBuild text = ms_strbuild_new();
  if (error->os_error == 2) {
    ms_strbuild_append_text(&text, "file not found: ");
    ms_strbuild_append(&text, shown);
    ms_strbuild_append_text(&text, "; check the path and run from the directory that contains it");
    return arena_text(arena, &text);
  }
  ms_strbuild_free(&text);
  return ms_project_error_text(arena, &named);
}


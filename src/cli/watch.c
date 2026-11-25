/* Owns the change polling of watch.h: a signature of each watched path (size, modification time, mode) compared every
 * few milliseconds. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "cli/watch.h"

#include <uv.h>

#include "base/message.h"
#include "base/ostext.h"
#include "base/path.h"
#include "base/strbuild.h"


enum { POLL_MS = 10, MS_PER_SECOND = 1000, NS_PER_MS = 1000000 };

uint64_t watch_now_ms(void) {
  uv_timeval64_t now;
  (void)uv_gettimeofday(&now);
  return (uint64_t)now.tv_sec * MS_PER_SECOND + (uint64_t)now.tv_usec / MS_PER_SECOND;
}

/* Appends the state of `path`; true when it was modified at or after `started_ms`. */
static bool append_state(MsStrBuild *signature, MsSpan path, uint64_t started_ms) {
  MsOsText name = ms_os_text_new(path);
  uv_fs_t request;
  const int result = uv_fs_stat(NULL, &request, name.ptr, NULL);
  bool late = false;
  if (result < 0) {
    ms_strbuild_append_text(signature, "-\n");
  } else {
    const uv_stat_t *stat = uv_fs_get_statbuf(&request);
    const uint64_t modified = (uint64_t)stat->st_mtim.tv_sec * MS_PER_SECOND + (uint64_t)stat->st_mtim.tv_nsec / NS_PER_MS;
    late = modified >= started_ms;
    ms_strbuild_printf(signature, "%llu %llu.%09llu %llu\n", (unsigned long long)stat->st_size,
                       (unsigned long long)stat->st_mtim.tv_sec, (unsigned long long)stat->st_mtim.tv_nsec,
                       (unsigned long long)stat->st_mode);
  }
  uv_fs_req_cleanup(&request);
  ms_os_text_free(&name);
  return late;
}

static bool snapshot(const MsSpanList *paths, uint64_t started_ms, MsStrBuild *signature) {
  bool late = false;
  for (size_t i = 0; i < paths->len; i++) {
    late = append_state(signature, paths->ptr[i], started_ms) || late;
  }
  return late;
}

/* Whether the paths still read as `signature` says. */
static bool unchanged(const MsSpanList *paths, MsStrBuild *signature) {
  MsStrBuild current = ms_strbuild_new();
  (void)snapshot(paths, UINT64_MAX, &current);
  const bool same = ms_span_equal(ms_strbuild_span(&current), ms_strbuild_span(signature));
  ms_strbuild_free(signature);
  *signature = current;
  return same;
}

void watch_snapshot(const MsSpanList *paths, MsStrBuild *signature) { (void)snapshot(paths, UINT64_MAX, signature); }

bool watch_changed(const MsSpanList *paths, MsStrBuild *signature) { return !unchanged(paths, signature); }

void watch_settle(const MsSpanList *paths, MsStrBuild *signature) {
  do {
    uv_sleep(POLL_MS);
  } while (watch_changed(paths, signature));
}

void watch_wait(const MsSpanList *paths, uint64_t started_ms) {
  MsStrBuild signature = ms_strbuild_new();
  if (!snapshot(paths, started_ms, &signature)) {
    while (unchanged(paths, &signature)) {
      uv_sleep(POLL_MS);
    }
    do {
      uv_sleep(POLL_MS);
    } while (!unchanged(paths, &signature));
  }
  ms_strbuild_free(&signature);
}

/* The files a rerun depends on: the input, its manifest, every local module and the directory of each, where a new
 * file would appear. */
void watch_add_inputs(MsArena *arena, MsSpan input, const MsGraph *graph, MsSpanList *watched) {
  ms_span_list_push(watched, input);
  if (graph->project_root.len != 0) {
    MsStrBuild manifest = ms_strbuild_new();
    ms_path_append_joined(&manifest, graph->project_root, ms_span_of_text("ms.toml"));
    ms_span_list_push(watched, ms_message_from_builder(arena, &manifest));
    ms_strbuild_free(&manifest);
  }
  if (graph->source_root.len != 0) {
    ms_span_list_push(watched, graph->source_root);
  }
  for (size_t i = 0; i < graph->count; i++) {
    const MsGraphModule *module = &graph->modules[i];
    if (!ms_span_starts_with_text(module->name, "@")) {
      ms_span_list_push(watched, module->path);
      ms_span_list_push(watched, ms_path_parent(module->path));
    }
  }
}

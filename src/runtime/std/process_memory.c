/* @std/process memory_usage: its own unit so that a program that never asks for the heap figure neither links it nor
 * pays for it: the constructor below starts the allocator's live-byte count before main. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include <uv.h>

#include "base/alloc.h"
#include "runtime/core/alloc.h"
#include "runtime/std/fail.h"
#include "runtime/std/process.h"

__attribute__((constructor)) static void track_heap(void) { ms_alloc_track_live(); }

/* A byte count from libuv as a signed one; a limit libuv reports as "none" (the largest value) is 0. */
static int64_t counted(uint64_t bytes) { return bytes > (uint64_t)INT64_MAX ? 0 : (int64_t)bytes; }

static uint8_t fail_host(int code, const char *operation, MsString *err) {
  MsFail fail = ms_fail_new();
  ms_fail_uv(&fail, code, operation, ms_span_of(NULL, 0));
  return ms_fail_finish(&fail, err);
}

uint8_t msstd_process_memory_usage(MsProcessMemory *out, MsString *err) {
  size_t resident = 0;
  const int code = uv_resident_set_memory(&resident);
  if (code != 0) {
    return fail_host(code, "resident memory", err);
  }
  int64_t used = 0;
  int64_t committed = 0;
  ms_core_heap_stats(&used, &committed);
  const int64_t total = counted(resident);
  *out = (MsProcessMemory){
    .heap_used = used,
    .heap_total = committed,
    .heap_system = committed,
    .external = total > committed ? total - committed : 0,
    .resident = total,
  };
  MsFail done = ms_fail_new();
  return ms_fail_finish(&done, err);
}


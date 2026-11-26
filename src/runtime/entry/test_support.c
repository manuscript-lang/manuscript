/* The test runner's calls (see test_support.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "runtime/entry/test_support.h"

#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <uv.h>

#include "abi/fault.h"
#include "base/alloc.h"
#include "base/fatal.h"
#include "base/file.h"
#include "base/desc.h"
#include "runtime/core/fault_kept.h"
#include "runtime/core/record.h"
#include "base/ostext.h"
#include "runtime/core/task.h"
#include "runtime/io/stdout.h"
#include "runtime/sys/sys.h"

enum { ENV_BYTES = 32, RECORD_MODE = 0644 };

static _Atomic int64_t test_timeout_ns = -1; /* -1 until the environment was read */

/* The decimal value of environment variable `name`, or -1 when it is unset or not a non-negative number. */
static int64_t env_number(const char *name) {
  char text[ENV_BYTES];
  size_t size = sizeof text;
  if (uv_os_getenv(name, text, &size) != 0) {
    return -1;
  }
  char *end = NULL;
  const long long value = strtoll(text, &end, 10);
  return end != text && *end == '\0' && value >= 0 ? value : -1;
}

void msrt_test_deadline(bool on) {
  int64_t timeout = atomic_load_explicit(&test_timeout_ns, memory_order_relaxed);
  if (timeout < 0) {
    timeout = env_number("MS_TEST_TIMEOUT_NS");
    timeout = timeout > 0 ? timeout : 0;
    atomic_store_explicit(&test_timeout_ns, timeout, memory_order_relaxed);
  }
  int64_t at = MS_NO_DEADLINE;
  if (on && timeout > 0) {
    const int64_t now = ms_sys_monotonic_ns();
    at = now > INT64_MAX - timeout ? MS_NO_DEADLINE : now + timeout;
  }
  (void)ms_task_set_defer_deadline(at);
}

/* Writes `data` to `file` with one write; false when it did not all go. */
static bool write_whole(uv_file file, MsSpan data) {
  uv_fs_t request;
  const uv_buf_t buffer = uv_buf_init((char *)(uintptr_t)data.ptr, (unsigned int)data.len);
  const int written = uv_fs_write(NULL, &request, file, &buffer, 1, -1, NULL);
  uv_fs_req_cleanup(&request);
  return written >= 0 && (size_t)written == data.len;
}

/* One byte to the descriptor MS_TEST_WAKE names (a handle on Windows), so the supervisor knows a record
 * arrived. Nothing without the variable. */
static void ring_bell(void) {
  static _Atomic int64_t bell = -2; /* -2: not read yet, -1: none */
  int64_t descriptor = atomic_load_explicit(&bell, memory_order_relaxed);
  if (descriptor == -2) {
    descriptor = env_number("MS_TEST_WAKE");
#ifdef _WIN32
    if (descriptor >= 0) {
      descriptor = uv_open_osfhandle((uv_os_fd_t)(uintptr_t)descriptor);
    }
#endif
    atomic_store_explicit(&bell, descriptor, memory_order_relaxed);
  }
  if (descriptor >= 0) {
    static const uint8_t byte = 1;
    (void)write_whole((uv_file)descriptor, ms_span_of(&byte, 1));
  }
}

void msrt_test_record(const MsString *path, const MsString *text) {
  MsOsText name = ms_os_text_new(ms_string_span(path));
  uv_fs_t request;
  const uv_file file = uv_fs_open(NULL, &request, name.ptr, UV_FS_O_WRONLY | UV_FS_O_CREAT | UV_FS_O_APPEND,
                                  RECORD_MODE, NULL);
  uv_fs_req_cleanup(&request);
  ms_os_text_free(&name);
  if (file < 0) {
    return;
  }
  if (write_whole(file, ms_string_span(text))) {
    ring_bell();
  }
  (void)ms_file_close_fd(file);
}

void msrt_test_failure(const MsString *message, const MsMap *details) {
  const MsString key = ms_string_from_span(ms_span_of_text("site"));
  const MsString *const site = (const MsString *)(const void *)ms_map_get(
      details, &ms_desc_string, &ms_desc_string, (const uint8_t *)&key);
  const MsSpan reason = ms_string_span(message);
  const MsSpan where = site != NULL ? ms_string_span(site) : ms_span_of(NULL, 0);
  ms_stdout_flush();
  ms_sys_stderr_write(reason);
  if (site != NULL) {
    ms_sys_stderr_write(ms_span_of_text("\n  at "));
    ms_sys_stderr_write(where);
  }
  ms_sys_stderr_write(ms_span_of_text("\n"));
  ms_fault_record_write(MS_FAULT_KIND_TEST_FAILURE, reason, site != NULL, where);
  MsString owned = key;
  ms_string_release(&owned);
}

/* Readable bytes, then as many unreadable: a multiple of every page size the platforms use (4, 16 and 64 KiB). */
enum { EDGE_PAGE = 64 * 1024 };

void msrt_test_edge_string(const MsString *text, MsString *out) {
  const MsSpan bytes = ms_string_span(text);
  uint8_t *const region = bytes.len > EDGE_PAGE ? NULL : ms_sys_map_anon(2 * EDGE_PAGE);
  if (region == NULL || !ms_sys_commit(region, EDGE_PAGE) || !ms_sys_guard(region + EDGE_PAGE, EDGE_PAGE)) {
    ms_fatal(MS_FATAL_OUT_OF_MEMORY, "msrt_test_edge_string: no guard page");
  }
  uint8_t *const start = region + EDGE_PAGE - bytes.len;
  if (bytes.len > 0) {
    memcpy(start, bytes.ptr, bytes.len);
  }
  *out = ms_string_view(ms_span_of(start, bytes.len));
}

void msrt_test_capture_fault(int64_t id, MsString *out) {
  uint8_t *bytes = NULL;
  size_t length = 0;
  ms_test_take_fault((uint64_t)id, &bytes, &length);
  *out = length == 0 ? ms_string_empty() : ms_string_from_span(ms_span_of(bytes, length));
  ms_free(bytes);
}

static _Atomic uint8_t bench_sink;

void msstd_bench_sink(const MsShapeTable *table, const void *value) {
  (void)table;
  atomic_store_explicit(&bench_sink, *(const volatile uint8_t *)value, memory_order_relaxed);
}

/* The @std/process natives for the running process: signals sent, identity, resource usage and title. libuv answers what
 * it wraps (memory, rusage, kill); the rest (groups, identity) goes through src/runtime/sys. Nothing here
 * blocks, so it all runs on the runtime thread. The working directory and the environment are in process_env.c. */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "runtime/std/process.h"

#include <stdatomic.h>
#include <uv.h>

#include "base/alloc.h"
#include "base/list.h"
#include "base/ostext.h"
#include "base/strbuild.h"
#include "base/utf8.h"
#include "runtime/core/alloc.h"
#include "runtime/entry/entry.h"
#include "runtime/io/stop.h"
#include "runtime/std/fail.h"
#include "runtime/sys/process.h"
#include "runtime/sys/sys.h"

enum {
  MAX_ID = 2147483647,
  MAX_SIGNAL = 64,
  FIRST_PATH = 1024,
  TITLE_LIMIT = 4096,
  SIGNAL_INTERRUPT = 2,
  SIGNAL_TERMINATE = 15,
  KILOBYTE = 1024,
  MICROSECONDS_PER_SECOND = 1000000,
};

static MsSpan no_name(void) { return ms_span_of(NULL, 0); }

static uint8_t invalid(MsString *err) {
  MsFail fail = ms_fail_new();
  ms_fail_status(&fail, MS_STATUS_INVALID_INPUT);
  return ms_fail_finish(&fail, err);
}

/* A host failure `code` (a libuv status) of `operation`, ending the native. */
static uint8_t fail_host(int code, const char *operation, MsString *err) {
  MsFail fail = ms_fail_new();
  ms_fail_uv(&fail, code, operation, no_name());
  return ms_fail_finish(&fail, err);
}

static uint8_t succeed(MsString *err) {
  MsFail fail = ms_fail_new();
  return ms_fail_finish(&fail, err);
}

static bool in_id_range(int64_t value) { return value >= 0 && value <= MAX_ID; }

static MsString text_of(const char *text) { return ms_string_from_span(ms_span_of_text(text)); }

/* ---- signals sent ---- */

uint8_t msstd_process_send_signal(int64_t pid, int64_t signal, MsString *err) {
  if (pid < INT32_MIN || pid > INT32_MAX || signal < 0 || signal > MAX_SIGNAL) {
    return invalid(err);
  }
  /* A process cannot signal itself on Windows (`kill` ends it), so SIGINT and SIGTERM sent to its own id are delivered
   * as the stop request and to the observers, as POSIX delivers them. */
  if (ms_sys_signal_self_by_raise() && pid == (int64_t)uv_os_getpid() &&
      (signal == SIGNAL_INTERRUPT || signal == SIGNAL_TERMINATE)) {
    ms_io_stop_raise((int)signal);
    ms_sys_signal_raise((int)signal);
    return succeed(err);
  }
  const int code = uv_kill((int)pid, (int)signal);
  if (code == UV_ESRCH) {
    MsFail fail = ms_fail_new();
    ms_fail_status(&fail, MS_STATUS_NOT_FOUND); /* the same NotFound on every platform */
    return ms_fail_finish(&fail, err);
  }
  return code != 0 ? fail_host(code, "kill", err) : succeed(err);
}

/* ---- identity ---- */

static MsList list_of_ids(const int64_t *ids, size_t count) {
  MsList list = {0};
  ms_list_reserve(&list, sizeof(int64_t), count);
  for (size_t i = 0; i < count; i++) {
    ms_list_push(&list, sizeof(int64_t), &ids[i]);
  }
  return list;
}

uint8_t msstd_process_groups(MsList *out, MsString *err) {
  int64_t *groups = NULL;
  size_t count = 0;
  const int code = ms_sys_process_groups(&groups, &count);
  if (code != 0) {
    return fail_host(code, "getgroups", err);
  }
  *out = list_of_ids(groups, count);
  ms_free(groups);
  return succeed(err);
}

static uint8_t apply_groups(const int64_t *groups, size_t count, MsString *err) {
  const int code = ms_sys_process_set_groups(groups, count);
  return code != 0 ? fail_host(code, "setgroups", err) : succeed(err);
}

uint8_t msstd_process_set_groups(const MsList *groups, MsString *err) {
  const int64_t *list = (const int64_t *)(const void *)groups->ptr;
  for (size_t i = 0; i < groups->len; i++) {
    if (!in_id_range(list[i])) {
      return invalid(err);
    }
  }
  return apply_groups(list, groups->len, err);
}

static bool has_byte(MsSpan span, uint8_t byte) {
  size_t at = 0;
  return ms_span_find(span, ms_span_of(&byte, 1), &at);
}

/* `gid` first, then the groups of `username`, each once. */
uint8_t msstd_process_initialize_groups(const MsString *username, int64_t gid, MsString *err) {
  const MsSpan name = ms_string_span(username);
  if (!in_id_range(gid) || name.len == 0 || has_byte(name, 0)) {
    return invalid(err);
  }
  MsOsText text = ms_os_text_new(name);
  int64_t *found = NULL;
  size_t count = 0;
  const int code = ms_sys_process_user_groups(text.ptr, &found, &count);
  ms_os_text_free(&text);
  if (code == UV_ENOENT) {
    MsFail fail = ms_fail_new();
    MsStrBuild message = ms_strbuild_new();
    ms_strbuild_append_text(&message, "user: unknown user ");
    ms_strbuild_append(&message, name);
    ms_fail_free(&fail);
    fail.status = MS_STATUS_FAILED;
    fail.message = ms_strbuild_finish(&message);
    ms_strbuild_free(&message);
    return ms_fail_finish(&fail, err);
  }
  if (code != 0) {
    return fail_host(code, "getgrouplist", err);
  }
  int64_t *groups = ms_alloc((count + 1) * sizeof *groups);
  size_t total = 0;
  groups[total++] = gid;
  for (size_t i = 0; i < count; i++) {
    bool seen = false;
    for (size_t j = 0; j < total && !seen; j++) {
      seen = groups[j] == found[i];
    }
    if (!seen) {
      groups[total++] = found[i];
    }
  }
  ms_free(found);
  const uint8_t status = apply_groups(groups, total, err);
  ms_free(groups);
  return status;
}

uint8_t msstd_process_set_identity(const MsString *kind, int64_t id, MsString *err) {
  static const struct {
    const char *name;
    MsSysIdentity which;
  } kinds[] = {{"uid", MS_SYS_ID_UID}, {"gid", MS_SYS_ID_GID}, {"euid", MS_SYS_ID_EUID}, {"egid", MS_SYS_ID_EGID}};
  const MsSpan text = ms_string_span(kind);
  if (!in_id_range(id)) {
    return invalid(err);
  }
  for (size_t i = 0; i < sizeof kinds / sizeof kinds[0]; i++) {
    if (ms_span_is_text(text, kinds[i].name)) {
      const int code = ms_sys_process_set_identity(kinds[i].which, (uint32_t)id);
      return code != 0 ? fail_host(code, "set identity", err) : succeed(err);
    }
  }
  return invalid(err);
}

/* ---- title ---- */

uint8_t msstd_process_title(MsString *out, MsString *err) {
  char buffer[TITLE_LIMIT];
  const int code = uv_get_process_title(buffer, sizeof buffer);
  if (code != 0) {
    return fail_host(code, "title", err);
  }
  const MsSpan text = ms_span_of_text(buffer);
  if (!ms_utf8_is_valid(text.ptr, text.len)) {
    MsFail fail = ms_fail_new();
    ms_fail_status(&fail, MS_STATUS_UNSUPPORTED);
    return ms_fail_finish(&fail, err);
  }
  *out = ms_string_from_span(text);
  return succeed(err);
}

uint8_t msstd_process_set_title(const MsString *title, MsString *err) {
  const MsSpan text = ms_string_span(title);
  if (has_byte(text, 0) || has_byte(text, '\n')) {
    return invalid(err);
  }
  char *copy = ms_alloc(text.len + 1);
  __builtin_memcpy(copy, text.ptr, text.len);
  copy[text.len] = '\0';
  const int code = uv_set_process_title(copy);
  ms_free(copy);
  return code != 0 ? fail_host(code, "set title", err) : succeed(err);
}

/* ---- memory and usage ---- */

/* A byte count from libuv as a signed one; a limit libuv reports as "none" (the largest value) is 0. */
static int64_t counted(uint64_t bytes) { return bytes > (uint64_t)INT64_MAX ? 0 : (int64_t)bytes; }

uint8_t msstd_process_constrained_memory(int64_t *out, MsString *err) {
  *out = counted(uv_get_constrained_memory());
  return succeed(err);
}

uint8_t msstd_process_available_memory(int64_t *out, MsString *err) {
  *out = counted(uv_get_available_memory());
  return succeed(err);
}

static int64_t micros(uv_timeval_t time) { return (int64_t)time.tv_sec * MICROSECONDS_PER_SECOND + (int64_t)time.tv_usec; }

uint8_t msstd_process_resource_usage(MsProcessResources *out, MsString *err) {
  uv_rusage_t usage;
  const int code = uv_getrusage(&usage);
  if (code != 0) {
    return fail_host(code, "getrusage", err);
  }
  *out = (MsProcessResources){
    .user_microseconds = micros(usage.ru_utime),
    .system_microseconds = micros(usage.ru_stime),
    .max_resident_bytes = (int64_t)usage.ru_maxrss * KILOBYTE, /* libuv reports kilobytes on every host */
    .minor_faults = (int64_t)usage.ru_minflt,
    .major_faults = (int64_t)usage.ru_majflt,
    .filesystem_reads = (int64_t)usage.ru_inblock,
    .filesystem_writes = (int64_t)usage.ru_oublock,
    .voluntary_switches = (int64_t)usage.ru_nvcsw,
    .involuntary_switches = (int64_t)usage.ru_nivcsw,
  };
  return succeed(err);
}

uint8_t msstd_process_cpu_usage(MsProcessCpu *out, MsString *err) {
  uv_rusage_t usage;
  const int code = uv_getrusage(&usage);
  if (code != 0) {
    return fail_host(code, "getrusage", err);
  }
  *out = (MsProcessCpu){.user_microseconds = micros(usage.ru_utime), .system_microseconds = micros(usage.ru_stime)};
  return succeed(err);
}

/* ---- identity, memory and counters ---- */

#if defined(__APPLE__)
#define OS_NAME "darwin"
#elif defined(_WIN32)
#define OS_NAME "windows"
#else
#define OS_NAME "linux"
#endif

#if defined(__aarch64__) || defined(_M_ARM64)
#define ARCH_NAME "arm64"
#else
#define ARCH_NAME "amd64"
#endif

/* The path of the running executable; not UTF-8 is unsupported, as for every String the runtime hands out. */
static uint8_t executable_path(MsString *out, MsString *err) {
  size_t capacity = FIRST_PATH;
  char *buffer = ms_alloc(capacity);
  int code = 0;
  size_t size = 0;
  for (;;) {
    size = capacity;
    code = uv_exepath(buffer, &size);
    if (code != UV_ENOBUFS && !(code == 0 && size >= capacity - 1)) {
      break;
    }
    capacity *= 2;
    buffer = ms_realloc(buffer, capacity);
  }
  uint8_t status = MS_STATUS_OK;
  if (code != 0) {
    status = fail_host(code, "executable", err);
  } else if (!ms_utf8_is_valid((const uint8_t *)buffer, size)) {
    MsFail fail = ms_fail_new();
    ms_fail_status(&fail, MS_STATUS_UNSUPPORTED);
    status = ms_fail_finish(&fail, err);
  } else {
    *out = ms_string_from_span(ms_span_of((const uint8_t *)buffer, size));
    status = succeed(err);
  }
  ms_free(buffer);
  return status;
}

uint8_t msstd_process_info(MsProcessInfo *out, MsString *err) {
  MsString executable;
  const uint8_t status = executable_path(&executable, err);
  if (status != MS_STATUS_OK) {
    return status;
  }
  *out = (MsProcessInfo){
    .pid = (int64_t)uv_os_getpid(),
    .parent_pid = (int64_t)uv_os_getppid(),
    .executable = executable,
    .uid = ms_sys_process_identity(MS_SYS_ID_UID),
    .gid = ms_sys_process_identity(MS_SYS_ID_GID),
    .effective_uid = ms_sys_process_identity(MS_SYS_ID_EUID),
    .effective_gid = ms_sys_process_identity(MS_SYS_ID_EGID),
    .os = text_of(OS_NAME),
    .architecture = text_of(ARCH_NAME),
  };
  msrt_argv(&out->arguments);
  return status;
}

uint8_t msstd_process_runtime_counts(MsProcessCounts *out) {
  /* Allocations are the calling thread's; list and string copies are not counted; the executed operations come from an `--ops` build. */
  *out = (MsProcessCounts){.operations = ms_core_operations()};
  ms_alloc_counts(&out->allocations, &out->allocated_bytes);
  return MS_STATUS_OK;
}

/* Nanoseconds since the runtime started; a program that never recorded a start counts from its first call. */
int64_t msstd_process_uptime(void) {
  static _Atomic int64_t first;
  const int64_t now = ms_sys_monotonic_ns();
  int64_t origin = msrt_start_nanos();
  if (origin == 0) {
    int64_t unset = 0;
    (void)atomic_compare_exchange_strong(&first, &unset, now);
    origin = atomic_load(&first);
  }
  return now - origin;
}

uint8_t msstd_process_elapsed(int64_t *out) {
  *out = msstd_process_uptime();
  return MS_STATUS_OK;
}

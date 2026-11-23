/* Process state on Windows: no user or group ids, so those report unsupported. Errors are libuv statuses. */
#include <uv.h>

#define PSAPI_VERSION 2 /* GetProcessMemoryInfo from kernel32, so no extra library */
#include <windows.h>
#include <psapi.h>

#include <wchar.h>

#include "base/alloc.h"
#include "runtime/sys/process.h"

static int last_error(void) { return uv_translate_sys_error((int)GetLastError()); }

int64_t ms_sys_process_identity(MsSysIdentity which) {
  (void)which;
  return -1;
}

int ms_sys_process_groups(int64_t **list, size_t *count) {
  (void)list;
  (void)count;
  return UV_ENOTSUP;
}

int ms_sys_process_set_groups(const int64_t *list, size_t count) {
  (void)list;
  (void)count;
  return UV_ENOTSUP;
}

int ms_sys_process_set_identity(MsSysIdentity which, uint32_t id) {
  (void)which;
  (void)id;
  return UV_ENOTSUP;
}

int ms_sys_process_user_groups(const char *name, int64_t **list, size_t *count) {
  (void)name;
  (void)list;
  (void)count;
  return UV_ENOTSUP;
}

/* ---- a child process and what it leads ---- */

struct MsSysGroup {
  HANDLE job;
  HANDLE process;
  bool terminated; /* ended by ms_sys_group_signal: Windows reports that as an ordinary exit code */
};

MsSysGroup *ms_sys_group_new(int64_t pid, void *process_handle) {
  (void)pid;
  MsSysGroup *group = ms_alloc(sizeof *group);
  group->process = process_handle;
  group->terminated = false;
  group->job = CreateJobObjectW(NULL, NULL);
  if (group->job != NULL) {
    (void)AssignProcessToJobObject(group->job, process_handle);
  }
  return group;
}

void ms_sys_group_kill(MsSysGroup *group) {
  if (group->job != NULL) {
    (void)TerminateJobObject(group->job, 1);
  }
}

void ms_sys_group_signal(MsSysGroup *group, bool force) {
  (void)force;
  group->terminated = true;
  ms_sys_group_kill(group);
  (void)TerminateProcess(group->process, 1);
}

int64_t ms_sys_group_exit_code(const MsSysGroup *group, int64_t status, int signal) {
  return signal != 0 || group->terminated ? -1 : status;
}

int64_t ms_sys_group_peak_resident(const MsSysGroup *group, bool exited) {
  PROCESS_MEMORY_COUNTERS counters = {.cb = sizeof counters};
  if (exited && GetProcessMemoryInfo(group->process, &counters, sizeof counters)) {
    return (int64_t)counters.PeakWorkingSetSize;
  }
  return 0;
}

void ms_sys_group_free(MsSysGroup *group) {
  if (group->job != NULL) {
    (void)CloseHandle(group->job);
  }
  ms_free(group);
}

int ms_sys_process_exec(const char *file, char *const *argv, char *const *env) {
  (void)file;
  (void)argv;
  (void)env;
  return UV_ENOTSUP;
}

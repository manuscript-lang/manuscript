/* Process state on Windows: no user or group ids, so those report unsupported. Errors are libuv statuses. */
#include <uv.h>

#define PSAPI_VERSION 2 /* GetProcessMemoryInfo from kernel32, so no extra library */
#include <windows.h>
#include <psapi.h>

#include "base/alloc.h"
#include "runtime/sys/process.h"

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
  int64_t pid;
  HANDLE job;
  HANDLE process;
  bool terminated; /* ended by ms_sys_group_signal: Windows reports that as an ordinary exit code */
};

MsSysGroup *ms_sys_group_new(int64_t pid, void *process_handle) {
  MsSysGroup *group = ms_alloc(sizeof *group);
  group->pid = pid;
  /* libuv closes its handle before the exit callback runs: a copy keeps the process queryable until the group is freed. */
  group->process = NULL;
  if (!DuplicateHandle(GetCurrentProcess(), process_handle, GetCurrentProcess(), &group->process, 0, FALSE,
                       DUPLICATE_SAME_ACCESS)) {
    group->process = NULL;
  }
  group->terminated = false;
  group->job = CreateJobObjectW(NULL, NULL);
  if (group->job != NULL) {
    (void)AssignProcessToJobObject(group->job, process_handle);
  }
  return group;
}

enum { SIGNAL_INT = 2, SIGNAL_KILL = 9, SIGNAL_TERM = 15 };

typedef LONG(NTAPI *ProcessControl)(HANDLE);

/* NtSuspendProcess or NtResumeProcess on `pid`: the closest Windows has to SIGSTOP and SIGCONT. */
static int suspend_or_resume(int64_t pid, bool suspend) {
  HMODULE ntdll = GetModuleHandleW(L"ntdll.dll");
  ProcessControl control =
      ntdll == NULL ? NULL : (ProcessControl)(void *)GetProcAddress(ntdll, suspend ? "NtSuspendProcess" : "NtResumeProcess");
  if (control == NULL) {
    return UV_ENOTSUP;
  }
  HANDLE process = OpenProcess(PROCESS_SUSPEND_RESUME, FALSE, (DWORD)pid);
  if (process == NULL) {
    return GetLastError() == ERROR_INVALID_PARAMETER ? UV_ESRCH : UV_EACCES;
  }
  const LONG status = control(process);
  (void)CloseHandle(process);
  return status >= 0 ? 0 : UV_EPERM;
}

int ms_sys_kill_send(int64_t pid, MsSysKill signal) {
  switch (signal) {
  case MS_SYS_KILL_KILL:
    return uv_kill((int)pid, SIGNAL_KILL);
  case MS_SYS_KILL_TERMINATE:
    return uv_kill((int)pid, SIGNAL_TERM);
  case MS_SYS_KILL_INTERRUPT:
    /* Ctrl-Break only reaches a process group that shares this console, and reports success when it reaches nothing,
     * so Interrupt ends the process, the way libuv ends one for SIGINT. */
    return uv_kill((int)pid, SIGNAL_INT);
  case MS_SYS_KILL_STOP:
  case MS_SYS_KILL_CONTINUE:
    return suspend_or_resume(pid, signal == MS_SYS_KILL_STOP);
  default:
    return UV_ENOTSUP;
  }
}

int ms_sys_group_kill_send(MsSysGroup *group, MsSysKill signal) {
  if (signal == MS_SYS_KILL_KILL || signal == MS_SYS_KILL_TERMINATE || signal == MS_SYS_KILL_INTERRUPT) {
    ms_sys_group_signal(group, true);
    return 0;
  }
  return ms_sys_kill_send(group->pid, signal);
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
  if (group->process != NULL) {
    (void)TerminateProcess(group->process, 1);
  }
}

int64_t ms_sys_group_exit_code(const MsSysGroup *group, int64_t status, int signal) {
  return signal != 0 || group->terminated ? -1 : status;
}

int64_t ms_sys_group_peak_resident(const MsSysGroup *group, bool exited) {
  (void)exited;
  PROCESS_MEMORY_COUNTERS counters = {.cb = sizeof counters};
  if (group->process != NULL && GetProcessMemoryInfo(group->process, &counters, sizeof counters)) {
    return (int64_t)counters.PeakWorkingSetSize;
  }
  return 0;
}

void ms_sys_group_free(MsSysGroup *group) {
  if (group->process != NULL) {
    (void)CloseHandle(group->process);
  }
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

bool ms_sys_process_can_exec(void) { return false; }

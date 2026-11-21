/* Process state on Windows: no user or group ids and no umask, so those report unsupported; the title is the console
 * title. A process without a console keeps the title it was given in memory, as a program expects get_title to return
 * what set_title stored. Errors are libuv statuses. */
#include <uv.h>

#define PSAPI_VERSION 2 /* GetProcessMemoryInfo from kernel32, so no extra library */
#include <windows.h>
#include <psapi.h>

#include <wchar.h>

#include "base/alloc.h"
#include "runtime/sys/process.h"

enum { TITLE_UNITS = 32768 };

static SRWLOCK title_lock = SRWLOCK_INIT;
static char *stored_title; /* guarded by title_lock */
static size_t stored_length;

static int last_error(void) { return uv_translate_sys_error((int)GetLastError()); }

int64_t ms_sys_process_identity(MsSysIdentity which) {
  (void)which;
  return -1;
}

int ms_sys_process_umask(uint32_t mask, uint32_t *previous) {
  (void)mask;
  (void)previous;
  return UV_ENOTSUP;
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

static int utf8_of(const wchar_t *wide, int units, char **text, size_t *length) {
  const int needed = WideCharToMultiByte(CP_UTF8, 0, wide, units, NULL, 0, NULL, NULL);
  if (needed < 0) {
    return last_error();
  }
  char *bytes = ms_alloc((size_t)needed + 1);
  if (needed > 0 && WideCharToMultiByte(CP_UTF8, 0, wide, units, bytes, needed, NULL, NULL) == 0) {
    const int error = last_error();
    ms_free(bytes);
    return error;
  }
  *text = bytes;
  *length = (size_t)needed;
  return 0;
}

/* The executable's base name, the title of a process that has no console. */
static int executable_name(char **text, size_t *length) {
  wchar_t path[MAX_PATH];
  const DWORD units = GetModuleFileNameW(NULL, path, MAX_PATH);
  if (units == 0 || units >= MAX_PATH) {
    return last_error();
  }
  const wchar_t *base = path;
  for (const wchar_t *p = path; *p != 0; p++) {
    if (*p == L'\\' || *p == L'/') {
      base = p + 1;
    }
  }
  return utf8_of(base, (int)wcslen(base), text, length);
}

int ms_sys_process_title(char **text, size_t *length) {
  AcquireSRWLockShared(&title_lock);
  if (stored_title != NULL) {
    char *copy = ms_alloc(stored_length + 1);
    __builtin_memcpy(copy, stored_title, stored_length);
    *text = copy;
    *length = stored_length;
    ReleaseSRWLockShared(&title_lock);
    return 0;
  }
  ReleaseSRWLockShared(&title_lock);
  wchar_t *wide = ms_alloc(TITLE_UNITS * sizeof *wide);
  SetLastError(0);
  const DWORD units = GetConsoleTitleW(wide, TITLE_UNITS);
  int error = 0;
  if (units == 0 && GetLastError() != 0) {
    error = executable_name(text, length);
  } else {
    error = utf8_of(wide, (int)units, text, length);
  }
  ms_free(wide);
  return error;
}

int ms_sys_process_set_title(const char *text, size_t length) {
  const int units = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, (int)length, NULL, 0);
  if (units < 0 || (units == 0 && length > 0)) {
    return UV_EINVAL;
  }
  wchar_t *wide = ms_alloc(((size_t)units + 1) * sizeof *wide);
  if (units > 0) {
    (void)MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, (int)length, wide, units);
  }
  wide[units] = 0;
  const BOOL set = SetConsoleTitleW(wide);
  const DWORD error = set ? 0 : GetLastError();
  ms_free(wide);
  if (!set && error != ERROR_INVALID_HANDLE) {
    return uv_translate_sys_error((int)error);
  }
  char *copy = ms_alloc(length + 1);
  __builtin_memcpy(copy, text, length);
  AcquireSRWLockExclusive(&title_lock);
  ms_free(stored_title);
  stored_title = copy;
  stored_length = length;
  ReleaseSRWLockExclusive(&title_lock);
  return 0;
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

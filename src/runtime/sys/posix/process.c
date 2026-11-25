/* Process state on Linux and macOS: groups and identity. Errors are libuv statuses. */
#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <pwd.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <uv.h>

#include "base/alloc.h"
#include "runtime/sys/process.h"

#ifdef __APPLE__
typedef int MsGroupId; /* getgrouplist takes int on macOS */
typedef int MsGroupCount; /* setgroups takes int on macOS */
#else
typedef gid_t MsGroupId;
typedef size_t MsGroupCount;
#endif

enum { FIRST_GROUPS = 32, PASSWD_BUFFER = 1024 };

/* The libuv status of the failed system call that just set errno. */
static int last_error(void) { return uv_translate_sys_error(errno); }

int64_t ms_sys_process_identity(MsSysIdentity which) {
  switch (which) {
    case MS_SYS_ID_UID:
      return (int64_t)getuid();
    case MS_SYS_ID_GID:
      return (int64_t)getgid();
    case MS_SYS_ID_EUID:
      return (int64_t)geteuid();
    case MS_SYS_ID_EGID:
      return (int64_t)getegid();
  }
  return -1;
}

int ms_sys_process_groups(int64_t **list, size_t *count) {
  const int total = getgroups(0, NULL);
  if (total < 0) {
    return last_error();
  }
  gid_t *groups = ms_alloc(((size_t)total + 1) * sizeof *groups);
  const int got = getgroups(total, groups);
  if (got < 0) {
    const int error = last_error();
    ms_free(groups);
    return error;
  }
  int64_t *out = ms_alloc(((size_t)total + 1) * sizeof *out);
  for (int i = 0; i < got; i++) {
    out[i] = (int64_t)groups[i];
  }
  ms_free(groups);
  *list = out;
  *count = (size_t)got;
  return 0;
}

int ms_sys_process_set_groups(const int64_t *list, size_t count) {
  gid_t *groups = ms_alloc((count + 1) * sizeof *groups);
  for (size_t i = 0; i < count; i++) {
    groups[i] = (gid_t)list[i];
  }
  const int status = setgroups((MsGroupCount)count, groups);
  const int error = status == 0 ? 0 : last_error();
  ms_free(groups);
  return error;
}

int ms_sys_process_set_identity(MsSysIdentity which, uint32_t id) {
  int status = -1;
  switch (which) {
    case MS_SYS_ID_UID:
      status = setuid((uid_t)id);
      break;
    case MS_SYS_ID_GID:
      status = setgid((gid_t)id);
      break;
    case MS_SYS_ID_EUID:
      status = seteuid((uid_t)id);
      break;
    case MS_SYS_ID_EGID:
      status = setegid((gid_t)id);
      break;
  }
  return status == 0 ? 0 : last_error();
}

/* The primary group of user `name`, or a libuv status (UV_ENOENT for an unknown user). */
static int primary_group(const char *name, gid_t *group) {
  const long hint = sysconf(_SC_GETPW_R_SIZE_MAX);
  size_t size = hint > 0 ? (size_t)hint : PASSWD_BUFFER;
  char *text = ms_alloc(size);
  struct passwd record;
  struct passwd *entry = NULL;
  int status = getpwnam_r(name, &record, text, size, &entry);
  while (status == ERANGE) {
    size *= 2;
    text = ms_realloc(text, size);
    status = getpwnam_r(name, &record, text, size, &entry);
  }
  if (status == 0 && entry != NULL) {
    *group = entry->pw_gid;
  }
  ms_free(text);
  if (status != 0) {
    return uv_translate_sys_error(status);
  }
  return entry == NULL ? UV_ENOENT : 0;
}

int ms_sys_process_user_groups(const char *name, int64_t **list, size_t *count) {
  gid_t primary = 0;
  const int error = primary_group(name, &primary);
  if (error != 0) {
    return error;
  }
  int capacity = FIRST_GROUPS;
  MsGroupId *ids = ms_alloc((size_t)capacity * sizeof *ids);
  for (;;) {
    int found = capacity;
    if (getgrouplist(name, (MsGroupId)primary, ids, &found) >= 0) {
      int64_t *out = ms_alloc(((size_t)found + 1) * sizeof *out);
      for (int i = 0; i < found; i++) {
        out[i] = (int64_t)ids[i];
      }
      ms_free(ids);
      *list = out;
      *count = (size_t)found;
      return 0;
    }
    capacity = found > capacity ? found : capacity * 2;
    ids = ms_realloc(ids, (size_t)capacity * sizeof *ids);
  }
}

/* ---- a child process and what it leads ---- */

struct MsSysGroup {
  pid_t pid;
};

static int host_signal(MsSysKill signal) {
  static const int numbers[MS_SYS_KILL_COUNT] = {
      [MS_SYS_KILL_HANGUP] = SIGHUP,  [MS_SYS_KILL_INTERRUPT] = SIGINT, [MS_SYS_KILL_QUIT] = SIGQUIT,
      [MS_SYS_KILL_TERMINATE] = SIGTERM, [MS_SYS_KILL_KILL] = SIGKILL,   [MS_SYS_KILL_STOP] = SIGSTOP,
      [MS_SYS_KILL_CONTINUE] = SIGCONT, [MS_SYS_KILL_USER1] = SIGUSR1,  [MS_SYS_KILL_USER2] = SIGUSR2,
  };
  return numbers[signal];
}

int ms_sys_kill_send(int64_t pid, MsSysKill signal) { return uv_kill((int)pid, host_signal(signal)); }

int ms_sys_group_kill_send(MsSysGroup *group, MsSysKill signal) {
  return uv_kill(-(int)group->pid, host_signal(signal));
}

MsSysGroup *ms_sys_group_new(int64_t pid, void *process_handle) {
  (void)process_handle;
  MsSysGroup *group = ms_alloc(sizeof *group);
  group->pid = (pid_t)pid;
  return group;
}

void ms_sys_group_signal(MsSysGroup *group, bool force) {
  if (force || uv_kill(-(int)group->pid, SIGTERM) != 0) {
    (void)uv_kill(-(int)group->pid, SIGKILL);
  }
}

void ms_sys_group_kill(MsSysGroup *group) { (void)uv_kill(-(int)group->pid, SIGKILL); }

int64_t ms_sys_group_exit_code(const MsSysGroup *group, int64_t status, int signal) {
  (void)group;
  return signal != 0 ? -1 : status;
}

#ifdef __linux__
/* VmHWM of /proc/<pid>/status in bytes, 0 when unreadable. */
static int64_t high_water_mark(pid_t pid) {
  char path[64];
  (void)snprintf(path, sizeof path, "/proc/%lld/status", (long long)pid);
  FILE *file = fopen(path, "re");
  if (file == NULL) {
    return 0;
  }
  char line[256];
  int64_t kilobytes = 0;
  while (fgets(line, sizeof line, file) != NULL) {
    if (ms_span_starts_with(ms_span_of_text(line), ms_span_of_text("VmHWM:"))) {
      kilobytes = strtoll(line + 6, NULL, 10);
      break;
    }
  }
  (void)fclose(file);
  return kilobytes * 1024;
}
#endif

/* The most any child this process has reaped used, in bytes: an upper bound for one that exited before it was sampled. */
static int64_t reaped_peak(void) {
  struct rusage usage;
  if (getrusage(RUSAGE_CHILDREN, &usage) != 0) {
    return 0;
  }
#ifdef __APPLE__
  return (int64_t)usage.ru_maxrss; /* bytes */
#else
  return (int64_t)usage.ru_maxrss * 1024; /* kilobytes */
#endif
}

int64_t ms_sys_group_peak_resident(const MsSysGroup *group, bool exited) {
#ifdef __linux__
  if (!exited) {
    return high_water_mark(group->pid);
  }
#else
  (void)group;
#endif
  return exited ? reaped_peak() : 0;
}

void ms_sys_group_free(MsSysGroup *group) { ms_free(group); }

int ms_sys_process_exec(const char *file, char *const *argv, char *const *env) {
  (void)execve(file, argv, env);
  return last_error();
}

bool ms_sys_process_can_exec(void) { return true; }

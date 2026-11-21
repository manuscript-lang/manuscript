/* Process state on Linux and macOS: umask, groups, identity and the process title. Errors are libuv statuses. */
#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <pwd.h>
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

enum { FIRST_GROUPS = 32, TITLE_LIMIT = 4096, PASSWD_BUFFER = 1024 };

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

int ms_sys_process_umask(uint32_t mask, uint32_t *previous) {
  *previous = (uint32_t)umask((mode_t)mask);
  return 0;
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

#ifdef __linux__
static const char comm_path[] = "/proc/self/comm";

int ms_sys_process_title(char **text, size_t *length) {
  const int fd = open(comm_path, O_RDONLY | O_CLOEXEC);
  if (fd < 0) {
    return last_error();
  }
  char *buffer = ms_alloc(TITLE_LIMIT);
  const ssize_t got = read(fd, buffer, TITLE_LIMIT);
  const int error = got < 0 ? last_error() : 0;
  close(fd);
  if (got < 0) {
    ms_free(buffer);
    return error;
  }
  size_t size = (size_t)got;
  if (size > 0 && buffer[size - 1] == '\n') {
    size--;
  }
  *text = buffer;
  *length = size;
  return 0;
}

enum { COMM_LIMIT = 15 }; /* the longest Linux process title */

int ms_sys_process_set_title(const char *text, size_t length) {
  if (length > COMM_LIMIT) {
    return UV_ENAMETOOLONG;
  }
  const int fd = open(comm_path, O_WRONLY | O_TRUNC | O_CLOEXEC);
  if (fd < 0) {
    return last_error();
  }
  const ssize_t put = write(fd, text, length);
  const int error = put < 0 ? last_error() : 0;
  close(fd);
  return error;
}
#else
int ms_sys_process_title(char **text, size_t *length) {
  (void)text;
  (void)length;
  return UV_ENOTSUP;
}

int ms_sys_process_set_title(const char *text, size_t length) {
  (void)text;
  (void)length;
  return UV_ENOTSUP;
}
#endif

/* The `stat` family for glibc 2.28, which exports only `__xstat` and friends: its headers inline `stat` over them
 * and its `libc_nonshared.a` carries the out-of-line copies, which the glibc stubs we link do not. Linked into
 * programs (never into `ms`, whose host libc exports the real functions); on 64-bit targets `struct stat` is
 * `struct stat64`, so both names share one implementation. */
#define _GNU_SOURCE
#include <sys/stat.h>
#include <sys/types.h>

#ifdef _STAT_VER
extern int __xstat64(int version, const char *path, struct stat64 *buffer);
extern int __lxstat64(int version, const char *path, struct stat64 *buffer);
extern int __fxstat64(int version, int fd, struct stat64 *buffer);
extern int __fxstatat64(int version, int fd, const char *path, struct stat64 *buffer, int flags);
extern int __xmknod(int version, const char *path, mode_t mode, dev_t *device);
extern int __xmknodat(int version, int fd, const char *path, mode_t mode, dev_t *device);

int stat(const char *path, struct stat *buffer) {
  return __xstat64(_STAT_VER, path, (struct stat64 *)buffer);
}

int stat64(const char *path, struct stat64 *buffer) {
  return __xstat64(_STAT_VER, path, buffer);
}

int lstat(const char *path, struct stat *buffer) {
  return __lxstat64(_STAT_VER, path, (struct stat64 *)buffer);
}

int lstat64(const char *path, struct stat64 *buffer) {
  return __lxstat64(_STAT_VER, path, buffer);
}

int fstat(int fd, struct stat *buffer) {
  return __fxstat64(_STAT_VER, fd, (struct stat64 *)buffer);
}

int fstat64(int fd, struct stat64 *buffer) {
  return __fxstat64(_STAT_VER, fd, buffer);
}

int fstatat(int fd, const char *path, struct stat *buffer, int flags) {
  return __fxstatat64(_STAT_VER, fd, path, (struct stat64 *)buffer, flags);
}

int fstatat64(int fd, const char *path, struct stat64 *buffer, int flags) {
  return __fxstatat64(_STAT_VER, fd, path, buffer, flags);
}

int mknod(const char *path, mode_t mode, dev_t device) {
  return __xmknod(_MKNOD_VER, path, mode, &device);
}

int mknodat(int fd, const char *path, mode_t mode, dev_t device) {
  return __xmknodat(_MKNOD_VER, fd, path, mode, &device);
}
#endif

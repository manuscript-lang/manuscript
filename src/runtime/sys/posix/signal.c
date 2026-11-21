/* Signal observers on Linux and macOS. One handler per observed signal (installed with its first observer, removed with
 * its last) calls the handler that was installed before, then writes the signal number to the pipe of every observer of
 * that signal. A full pipe drops the signal. */
#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdatomic.h>
#include <unistd.h>
#include <uv.h>

#include "base/alloc.h"
#include "runtime/sys/process.h"

enum { SLOTS = 32, PIPE_LIMIT = 65536 };

struct MsSysSignals {
  int read_fd;
  int slot;
  uint64_t mask;
  bool stopped;
};

static atomic_int write_fd[SLOTS]; /* -1 when the slot is free; set up by ensure_slots */
static atomic_uint_least64_t slot_mask[SLOTS];
static atomic_int observers[MS_SYS_SIGNAL_MAX + 1];
static struct sigaction previous[MS_SYS_SIGNAL_MAX + 1];
static atomic_flag slots_ready = ATOMIC_FLAG_INIT;

static void ensure_slots(void) {
  if (!atomic_flag_test_and_set(&slots_ready)) {
    for (int i = 0; i < SLOTS; i++) {
      atomic_store(&write_fd[i], -1);
    }
  }
}

static void on_signal(int signal_number, siginfo_t *info, void *context) {
  const int saved = errno;
  /* The previous handler goes first: for SIGINT and SIGTERM it records the stop request. An observer woken by the byte
   * below could otherwise return from main before the request was recorded, and the program would exit 0 instead of
   * 128 plus the signal. */
  const struct sigaction *before = &previous[signal_number];
  if ((before->sa_flags & SA_SIGINFO) != 0) {
    if (before->sa_sigaction != NULL) {
      before->sa_sigaction(signal_number, info, context);
    }
  } else if (before->sa_handler != SIG_DFL && before->sa_handler != SIG_IGN) {
    before->sa_handler(signal_number);
  }
  const uint8_t byte = (uint8_t)signal_number;
  const uint64_t bit = UINT64_C(1) << (signal_number - 1);
  for (int i = 0; i < SLOTS; i++) {
    const int fd = atomic_load(&write_fd[i]);
    if (fd >= 0 && (atomic_load(&slot_mask[i]) & bit) != 0) {
      const ssize_t written = write(fd, &byte, 1); /* async-signal-safe; a full pipe drops the signal */
      (void)written;
    }
  }
  errno = saved;
}

static int install(int signal_number) {
  struct sigaction action = {0};
  action.sa_sigaction = on_signal;
  action.sa_flags = SA_SIGINFO | SA_RESTART;
  sigemptyset(&action.sa_mask);
  return sigaction(signal_number, &action, &previous[signal_number]) == 0 ? 0 : uv_translate_sys_error(errno);
}

static void restore(int signal_number) { (void)sigaction(signal_number, &previous[signal_number], NULL); }

bool ms_sys_signal_valid(int64_t signal_number) {
  return signal_number >= 1 && signal_number <= MS_SYS_SIGNAL_MAX && signal_number != SIGKILL &&
         signal_number != SIGSTOP;
}

/* A pipe whose ends are close-on-exec and non-blocking. */
static bool pipe_open(int fds[2]) {
#ifdef __linux__
  return pipe2(fds, O_CLOEXEC | O_NONBLOCK) == 0;
#else
  if (pipe(fds) != 0) {
    return false;
  }
  for (int i = 0; i < 2; i++) {
    const int flags = fcntl(fds[i], F_GETFL);
    if (fcntl(fds[i], F_SETFD, FD_CLOEXEC) != 0 || flags < 0 || fcntl(fds[i], F_SETFL, flags | O_NONBLOCK) != 0) {
      close(fds[0]);
      close(fds[1]);
      return false;
    }
  }
  return true;
#endif
}

/* Undoes the handlers installed for the signals of `mask` below `before`. */
static void uninstall_below(uint64_t mask, int before) {
  for (int signal_number = 1; signal_number < before; signal_number++) {
    if ((mask & (UINT64_C(1) << (signal_number - 1))) != 0 && atomic_fetch_sub(&observers[signal_number], 1) == 1) {
      restore(signal_number);
    }
  }
}

int ms_sys_signals_open(uint64_t mask, size_t capacity, MsSysSignalNotify notify, void *context, MsSysSignals **out) {
  (void)notify;
  (void)context;
  ensure_slots();
  int fds[2];
  if (!pipe_open(fds)) {
    return uv_translate_sys_error(errno);
  }
  int slot = -1;
  for (int i = 0; i < SLOTS && slot < 0; i++) {
    int free_slot = -1;
    if (atomic_compare_exchange_strong(&write_fd[i], &free_slot, fds[1])) {
      slot = i;
    }
  }
  if (slot < 0) {
    close(fds[0]);
    close(fds[1]);
    return MS_SYS_SIGNALS_FULL;
  }
#ifdef F_SETPIPE_SZ
  /* A larger pipe holds more buffered signals; failure keeps the default size. */
  (void)fcntl(fds[1], F_SETPIPE_SZ, (int)(capacity < PIPE_LIMIT ? capacity : PIPE_LIMIT));
#else
  (void)capacity;
#endif
  for (int signal_number = 1; signal_number <= MS_SYS_SIGNAL_MAX; signal_number++) {
    if ((mask & (UINT64_C(1) << (signal_number - 1))) == 0) {
      continue;
    }
    const int error = atomic_fetch_add(&observers[signal_number], 1) == 0 ? install(signal_number) : 0;
    if (error != 0) {
      atomic_fetch_sub(&observers[signal_number], 1);
      uninstall_below(mask, signal_number);
      atomic_store(&write_fd[slot], -1);
      close(fds[0]);
      close(fds[1]);
      return error;
    }
  }
  MsSysSignals *observer = ms_alloc_zeroed(sizeof *observer);
  observer->read_fd = fds[0];
  observer->slot = slot;
  observer->mask = mask;
  atomic_store(&slot_mask[slot], mask);
  *out = observer;
  return 0;
}

size_t ms_sys_signals_take(MsSysSignals *observer, uint8_t *out, size_t capacity) {
  const ssize_t count = read(observer->read_fd, out, capacity);
  return count > 0 ? (size_t)count : 0;
}

/* Closing the write end on stop is a hang-up, which wakes a wait on the read end. */
int ms_sys_signals_fd(const MsSysSignals *observer) { return observer->read_fd; }

bool ms_sys_signals_pending(const MsSysSignals *observer) {
  (void)observer;
  return false; /* the descriptor says so */
}

void ms_sys_signals_stop(MsSysSignals *observer) {
  if (observer->stopped) {
    return;
  }
  observer->stopped = true;
  atomic_store(&slot_mask[observer->slot], 0);
  uninstall_below(observer->mask, MS_SYS_SIGNAL_MAX + 1);
  const int fd = atomic_exchange(&write_fd[observer->slot], -1);
  close(fd);
}

void ms_sys_signals_destroy(MsSysSignals *observer) {
  ms_sys_signals_stop(observer);
  close(observer->read_fd);
  ms_free(observer);
}

void ms_sys_signal_raise(int signal_number) { (void)signal_number; /* a signal a process sends itself arrives by itself */ }
bool ms_sys_signal_self_by_raise(void) { return false; }

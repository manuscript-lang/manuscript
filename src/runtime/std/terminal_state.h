/* runtime/std/terminal_state.h: the shared raw terminal that terminal.c opens and terminal_read.c waits on. */
#ifndef MS_RUNTIME_STD_TERMINAL_STATE_H
#define MS_RUNTIME_STD_TERMINAL_STATE_H

#include <stdatomic.h>
#include <uv.h>

#include "base/desc.h"
#include "base/strbuild.h"

enum { MS_TERMINAL_INPUT_FD = 0, MS_TERMINAL_OUTPUT_FD = 1, MS_TERMINAL_ERROR_FD = 2, MS_UTF8_MAX = 4 };

/* Which parts of a terminal were set up, so a failed open releases exactly those. */
enum {
  MS_TERMINAL_LOOP = 1u << 0,
  MS_TERMINAL_INPUT = 1u << 1,
  MS_TERMINAL_OUTPUT = 1u << 2,
  MS_TERMINAL_WAKE = 1u << 3,
  MS_TERMINAL_RESIZE = 1u << 4,
  MS_TERMINAL_RAW = 1u << 5,
};

/* A raw terminal shared by its handles and by the read waits that are running. */
typedef struct MsTerminal {
  _Atomic uint32_t references; /* handles and running reads; the last release destroys it */
  _Atomic uint32_t handles;    /* handles alone; the last one's drop closes the terminal */
  _Atomic bool closed;         /* set once, by close */
  _Atomic bool abandoned;      /* the running read job's caller gave up (timeout or cancel): it reads nothing more */
  uint32_t parts;              /* MS_TERMINAL_* bits, set while opening and read while destroying */
  bool input_was_nonblocking;  /* the descriptors' modes before libuv reopened them, put back at destroy */
  bool output_was_nonblocking;
  uv_mutex_t read_lock; /* held by a read job from start to end: an abandoned job may still be ending when the next starts */
  uv_loop_t loop;       /* runs only inside a read wait, one at a time per terminal */
  uv_tty_t input;       /* on `loop` */
  uv_tty_t output;      /* writes only; used from the runtime thread */
  uv_async_t wake;      /* the one handle another thread may use: uv_async_send ends a wait */
  uv_signal_t resize;   /* SIGWINCH, started for the life of the terminal so a resize between waits is kept */
  MsStrBuild restore;   /* written at close; runtime thread only */
  MsStrBuild text;      /* the text the last read delivered; runtime thread only */
  uint8_t carry[MS_UTF8_MAX];
  size_t carry_length; /* bytes of an incomplete scalar kept for the next read; runtime thread only */
} MsTerminal;

/* The handle a program holds: the header the runtime drops it through, then the shared terminal. */
typedef struct MsTerminalHandle {
  MsObj header; /* must be first */
  MsTerminal *terminal;
} MsTerminalHandle;

void ms_terminal_retain(MsTerminal *terminal);
void ms_terminal_release(MsTerminal *terminal);
/* The raw terminal holding the host terminal, or NULL. */
MsTerminal *ms_terminal_active(void);

/* Waits on a pool thread for input and decodes it into `terminal->text` (terminal_read.c). */
uint8_t ms_terminal_read(MsTerminal *terminal, bool quick);

#endif

/* base/fatal.h: the one way library code reports a condition it cannot recover from (allocation failure,
 * arithmetic overflow, a bad index).
 *
 * `base` never decides what a fatal condition means. The program installs a handler: the runtime raises a
 * Manuscript fault, the compiler and tools keep the default, which prints the message and exits with the
 * C-style fault status. The handler must not return. */
#ifndef MS_BASE_FATAL_H
#define MS_BASE_FATAL_H

#include "base/safe.h"

typedef enum MsFatalKind {
  MS_FATAL_OUT_OF_MEMORY,
  MS_FATAL_OVERFLOW,
  MS_FATAL_OUT_OF_RANGE,
  MS_FATAL_INVARIANT
} MsFatalKind;

/* Exit statuses of the default handler, the same on every platform (C-style: 134 fault, 139 out of memory).
 * src/abi re-exports these; they are defined once, here. */
enum { MS_EXIT_FAULT = 134, MS_EXIT_RESOURCE = 139 };

/* Receives the kind and a static message. Must not return. */
typedef void (*MsFatalHandler)(MsFatalKind kind, MsSpan message);

/* Replaces the handler; NULL restores the default. Call before any other thread starts. */
void ms_fatal_install(MsFatalHandler handler);

/* Reports the condition through the installed handler; never returns. `message` is a string literal. */
MS_NORETURN void ms_fatal(MsFatalKind kind, const char *message);

#endif

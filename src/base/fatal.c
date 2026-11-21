/* Owns the fatal handler hook and the default handler (see fatal.h). */
#include "base/fatal.h"

#include <stdio.h>
#include <stdlib.h>

/* The one mutable global of base: set once at start-up, before threads. */
static MsFatalHandler installed_handler = NULL;

static MS_NORETURN void default_handler(MsFatalKind kind, MsSpan message) {
  (void)fwrite("fatal: ", 1, 7, stderr);
  if (message.len != 0) {
    (void)fwrite(message.ptr, 1, message.len, stderr);
  }
  (void)fwrite("\n", 1, 1, stderr);
  exit(kind == MS_FATAL_OUT_OF_MEMORY ? MS_EXIT_RESOURCE : MS_EXIT_FAULT);
}

void ms_fatal_install(MsFatalHandler handler) {
  installed_handler = handler;
}

void ms_fatal(MsFatalKind kind, const char *message) {
  const MsFatalHandler handler = installed_handler != NULL ? installed_handler : default_handler;
  handler(kind, ms_span_of_text(message));
  abort(); /* a handler that returns breaks its contract */
}

/* Owns the fatal handler hook and the default handler (see fatal.h). */
#include "base/fatal.h"

#include <stdio.h>
#include <stdlib.h>
#ifdef _WIN32
#include <windows.h>
#endif

/* The one mutable global of base: set once at start-up, before threads. */
static MsFatalHandler installed_handler = NULL;

static MS_NORETURN void default_handler(MsFatalKind kind, MsSpan message) {
  (void)fwrite("fatal: ", 1, 7, stderr);
  if (message.len != 0) {
    (void)fwrite(message.ptr, 1, message.len, stderr);
  }
  (void)fwrite("\n", 1, 1, stderr);
#ifdef _WIN32
  { /* PROBE (#6274): module-relative frames of the fatal site */
    void *frames[48];
    const USHORT count = RtlCaptureStackBackTrace(0, 48, frames, NULL);
    const unsigned long long base = (unsigned long long)(uintptr_t)GetModuleHandleA(NULL);
    for (USHORT i = 0; i < count; i++) {
      (void)fprintf(stderr, "probe-frame 0x%llx\n", (unsigned long long)(uintptr_t)frames[i] - base);
    }
  }
#endif
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

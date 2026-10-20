/* Print hooks for MIR fixtures when linking the real ms-rt (which has no msrt_print_* symbols). */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#ifdef _WIN32
#include <io.h>
#define write _write
#else
#include <unistd.h>
#endif

static void out(const char *s, int n) { if (write(1, s, (size_t)n) < 0) {} }
void msrt_print_int(int64_t v) { char b[32]; out(b, snprintf(b, sizeof b, "%lld\n", (long long)v)); }
void msrt_print_float(double v) { char b[64]; out(b, snprintf(b, sizeof b, "%.17g\n", v)); }
void msrt_print_bool(uint8_t v) { out(v ? "true\n" : "false\n", v ? 5 : 6); }
void msrt_print_str(const uint8_t *s) {
  out((const char *)s + 32, (int)*(const int64_t *)(s + 16));
  out("\n", 1);
}

#include "callback.h"

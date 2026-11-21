/* Workaround for #4766 (delete when Windows libuv is built from pinned sources).
 * The two accessors MSYS2's libuv.a calls from its inline `_snwprintf_s`: the UCRT headers it was built with leave
 * them to the CRT, and llvm-mingw's libmingwex and libucrt do not define them, so the link fails without these.
 * The values are the option words the printf and scanf families read; zero is the CRT's default. */
#include <stdint.h>

uint64_t *__local_stdio_printf_options(void) {
    static uint64_t options;
    return &options;
}

uint64_t *__local_stdio_scanf_options(void) {
    static uint64_t options;
    return &options;
}

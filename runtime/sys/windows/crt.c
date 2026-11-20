/* A symbol the folded libuv expects from the C runtime.
 *
 * The MSYS2 libuv calls `_snwprintf_s`, which the UCRT headers inline over `__local_stdio_printf_options`; the
 * archive keeps a reference to that function, and the llvm-mingw link does not define it. This weak definition
 * is the one the headers would have made (a single options word), and a CRT that provides its own wins.
 * Remove it when the libuv build stops referencing the symbol (issue: Windows libuv needs __local_stdio_printf_options).
 */
#include <stdint.h>

#ifdef __GNUC__
__attribute__((weak))
#endif
uint64_t *__local_stdio_printf_options(void) {
    static uint64_t options;
    return &options;
}

/* Unit tests of src/runtime/std/terminal.c for a process whose standard streams are not terminals (the test runner
 * redirects them): capabilities report it, raw mode and the size refuse it. Raw mode on a real pseudo-terminal is
 * covered by crates/ms-cli/tests/terminal.rs. */
#include <stdio.h>

#include "ms_rt/terminal.h"
#include "fake_rt.h"

static int failures;
#define CHECK(cond) do { if (!(cond)) { printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

int main(void) {
    if (msstd_terminal_capabilities_input_is_terminal() != 0 || msstd_terminal_capabilities_output_is_terminal() != 0) {
        puts("ok (skipped: attached to a terminal)");
        return 0;
    }
    CHECK(msstd_terminal_capabilities_raw_mode() == 0);
    CHECK(msstd_terminal_capabilities_resize_events() == 0);
    CHECK(msstd_terminal_capabilities_colors() == 0);
    CHECK(msstd_terminal_size_status() == STATUS_NOT_TERMINAL);
    CHECK(msstd_terminal_size_columns() == 0 && msstd_terminal_size_rows() == 0);
    MsObj *handle = NULL;
    MsStr err;
    CHECK(msstd_terminal_raw_mode(&handle, &err) == STATUS_NOT_TERMINAL && handle == NULL);
    if (failures != 0) {
        printf("%d failures\n", failures);
        return 1;
    }
    puts("ok");
    return 0;
}

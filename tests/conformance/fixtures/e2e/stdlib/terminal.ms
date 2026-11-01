# conform: tags=control-flow,modules,stdlib-terminal,stdlib-testing,testing,tier-io,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/stdlib/terminal.ms
import expect_equal, expect_false, fail from "@std/test/test.ms"
import TerminalError, raw_mode, terminal_capabilities from "@std/io/io.ms"

test "redirected streams report no terminal and refuse raw mode":
    let capabilities = terminal_capabilities()
    if capabilities.raw_mode: return

    try expect_false(capabilities.colors != 0 and not capabilities.output_is_terminal)
    try expect_false(capabilities.resize_events)

    match raw_mode(alternate_screen: false):
        ok(active):
            var raw = active
            try raw.close()
            return fail("raw mode on redirected input")
        error(cause):
            try expect_equal(cause, TerminalError.NotTerminal)

# conform: tags=control-flow,formatter,modules,parser,stdlib-terminal,stdlib-testing,testing,tier-io,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/stdlib/terminal.ms
from "@std/test.ms" import expect_equal, expect_false, fail
from "@std/io.ms" import terminal, TerminalError

test "redirected streams report no terminal and refuse raw mode":
    let capabilities = terminal().capabilities()
    if capabilities.raw_mode: return

    try expect_false(capabilities.colors != 0 and not capabilities.output_is_terminal)
    try expect_false(capabilities.resize_events)

    let raw = terminal().raw_mode(alternate_screen: False)

    if let active = raw:
        active.close()
        return fail("raw mode on redirected input")

    try expect_equal(raw.err(), TerminalError.NotTerminal)

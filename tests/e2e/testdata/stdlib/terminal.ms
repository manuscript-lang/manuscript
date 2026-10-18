import {expect_equal, expect_false, fail} from "@std/testing.ms"
import {terminal, TerminalError} from "@std/terminal.ms"

test "redirected streams report no terminal and refuse raw mode":
    let capabilities = terminal().capabilities()
    if capabilities.raw_mode: return

    (capabilities.colors != 0 and not capabilities.output_is_terminal) | try expect_false
    capabilities.resize_events | try expect_false

    match terminal().raw_mode(alternate_screen: false):
        ok(raw):
            raw.close()
            return fail("raw mode on redirected input")
        error(cause):
            try expect_equal(cause, TerminalError.NotTerminal)

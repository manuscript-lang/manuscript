import expect_equal, expect_false, fail from "@std/test.ms"
import terminal, TerminalError from "@std/io.ms"

test "redirected streams report no terminal and refuse raw mode":
    let capabilities = terminal().capabilities()
    if capabilities.raw_mode: return

    try expect_false(capabilities.colors != 0 and not capabilities.output_is_terminal)
    try expect_false(capabilities.resize_events)

    match terminal().raw_mode(alternate_screen: false):
        ok(active):
            var raw = active
            raw.close()
            return fail("raw mode on redirected input")
        error(cause):
            try expect_equal(cause, TerminalError.NotTerminal)

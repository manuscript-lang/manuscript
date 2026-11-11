// conform: tags=control-flow,formatter,modules,parser,stdlib-terminal,stdlib-testing,testing,tier-io,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/stdlib/terminal.ms
import (
	raw_mode, terminal_capabilities from "@std/cli/terminal.ms",
	expect_equal, expect_false, fail from "@std/test/test.ms",
)

test "redirected streams report no terminal and refuse raw mode":
	capabilities := terminal_capabilities()
	if capabilities.raw_mode: return

	expect_false(capabilities.colors != 0 and not capabilities.output_is_terminal)?
	expect_false(capabilities.resize_events)?

	match raw_mode(alternate_screen: false):
		ok(active):
			var raw = active
			raw.close()?
			return fail("raw mode on redirected input")
		error(cause):
			expect_equal(cause, Error("terminal: not a terminal", kind: "ENOTTY"))?

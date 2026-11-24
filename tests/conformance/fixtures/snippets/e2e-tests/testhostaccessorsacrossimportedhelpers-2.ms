// conform: tags=control-flow,diagnostics,match,modules,stdlib-io,stdlib-time,tier-io
// conform: phase=check
// conform: origin=tests/e2e/e2e_test.go:444 TestHostAccessorsAcrossImportedHelpers
import (
	stdout from "@std/io/io.ms",
	monotonic from "@std/time.ms",

	close_output, now from "./helper.ms",
)

export fn main() Int {
	before := now()
	if monotonic().difference(before) < 0.milliseconds() {
		return 1
	}

	close_output()

	cause := match stdout().write("") {
		ok(_) => {
			return 3
		}
		error(cause) => cause
	}

	match cause {
		Closed => {
			return 0
		}
		_ => {
			return 4
		}
	}
}

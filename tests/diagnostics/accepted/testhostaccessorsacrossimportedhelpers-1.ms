// conform: tags=diagnostics,formatter,modules,stdlib-io,stdlib-time,tier-io
// conform: phase=check,parse
// conform: origin=tests/e2e/e2e_test.go:434 TestHostAccessorsAcrossImportedHelpers
import (
	stdout from "@std/io/io.ms",
	Instant, monotonic from "@std/time.ms",
)

export fn now() Instant {
	return monotonic()
}

export fn close_output() Void {
	void stdout().close()
}
// expect-exit: 0

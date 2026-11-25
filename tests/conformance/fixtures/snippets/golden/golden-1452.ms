// conform: tags=diagnostics
// conform: phase=check
import (
	stdout from "@std/io/io.ms",
	Instant, clock from "@std/time.ms",
)

export fn now() Instant {
	return clock().now()
}

export fn close_output() Void {
	stdout().close()
}

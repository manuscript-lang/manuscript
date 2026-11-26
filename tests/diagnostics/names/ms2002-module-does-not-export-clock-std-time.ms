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
// expect-error: MS2002 5:14-5:19 module does not export clock; @std/time.ms exports: Date, Deadline, Duration, Instant, Timestamp, deadline_after, from_calendar, hours, local_zone, microseconds, milliseconds, minutes, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/time.ms"'
// expect-error: MS2001 9:12 unknown binding clock; host handle getters were removed: import the operation itself, e.g. read_file from "@std/os/fs.ms", connect from "@std/net/net.ms", run from "@std/os/process.ms", now from "@std/time.ms"
// expect-error: MS3000 13:5 this statement discards Void!, so a failure would be lost; write a trailing '?' to propagate it, 'if value := x' or 'match' to handle it, or 'void ...' to drop it on purpose

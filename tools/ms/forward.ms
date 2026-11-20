// Passes SIGINT and SIGTERM on to a child while the command waits for it, as the Rust
// CLI did, so interrupting `ms profile` or `ms test` lets the program finish its
// cleanup instead of unwinding the command and killing the program with it.
import (
	Promise, promise from "@std/concurrency/promise.ms",
	StopHold, hold_stop, send_signal, watch_signals from "@std/os/process.ms",
)

// ms: allow_effect std.process.signal
fn relay(pid: Int) Void!:
	_hold := hold_stop()
	var signals = watch_signals([2, 15], none)?

	while true:
		next := signals.next()?
		if next.is_none(): break

		// A child that already ended is no longer there to signal.
		void send_signal(pid, next.get())

	return ok()

// Forwards each SIGINT and SIGTERM to process `pid` until the promise is dropped.
// The calling task holds stop requests back too, until `hold` closes.
// ms: allow_effect std.process.signal
export fn forward_signals(pid: Int) Promise[Void]:
	return promise(fn: relay(pid))

// Holds SIGINT and SIGTERM back from the calling task, so waiting for a child goes on.
// ms: allow_effect std.process.signal
export fn hold() StopHold:
	return hold_stop()

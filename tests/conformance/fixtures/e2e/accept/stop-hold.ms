// conform: tags=stdlib-process,tier-io
// conform: phase=run
// A task that holds SIGTERM back keeps waiting for its child, reads the signal as a
// value and runs on; the held request still ends the process once the hold closes, with
// the status of a stopped process.
import (
	hold_stop, spawn, watch_signals from "@std/os/process.ms",
	seconds from "@std/time.ms",
)

fn main() Void!:
	_hold := hold_stop()
	var signals = watch_signals([15], none)?
	child := spawn("sh", ["-c", "sleep 0.2; kill -TERM $PPID; sleep 0.2"])?
	status := child.wait()?
	print(f"child exited {status}")

	signal := signals.next(timeout: seconds(5))?
	print(f"read signal {signal}")

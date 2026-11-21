// conform: tags=stdlib-process,tier-io
// conform: phase=run
// The signal is sent to the process's own id, which every platform delivers as a stop request.
// A task that holds SIGTERM back keeps waiting for its child, reads the signal as a
// value and runs on; the held request still ends the process once the hold closes, with
// the status of a stopped process.
import (
	hold_stop, process_info, send_signal, spawn, watch_signals from "@std/os/process.ms",
	seconds from "@std/time.ms",
)

fn main() Void!:
	_hold := hold_stop()
	var signals = watch_signals([15], none)?
	child := spawn("sh", ["-c", "sleep 0.2"])?
	send_signal(process_info()?.pid, 15)?
	status := child.wait()?
	print(f"child exited {status}")

	signal := signals.next(timeout: seconds(5))?
	print(f"read signal {signal}")

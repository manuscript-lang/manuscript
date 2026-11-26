// conform: tags=scope-cleanup,stdlib-promise,tier-io
// conform: phase=run
import (
	PromiseOptions, promise, wait_first from "@std/concurrency/promise.ms",
	milliseconds, sleep from "@std/time.ms",
)

// Holds heap values across waits so a cancelled promise has something to release.
fn hold(label String) Int {
	var parts List[String] = []

	for i in 0..600 {
		parts.append(f"{label} {i}")
		void sleep(milliseconds(100)).wait()
	}

	return parts.length()
}

fn main() Void {
	slow := promise(() => ok(hold("timed out")))
	timed_out := slow.with(options: PromiseOptions(timeout: milliseconds(20))).wait()
	first := wait_first([promise(() => ok(hold("loser"))), promise(() => ok(4))])
	pending := promise(() => ok(hold("dropped")))
	void pending
	print(f"{timed_out.is_error()} {first.get_or(0)}")
}
// expect-exit: 0
// expect-stdout: true 4

// conform: tags=scope-cleanup,stdlib-promise,tier-io
// conform: phase=run
import (
	promise from "@std/concurrency/promise.ms",
	milliseconds, seconds, sleep from "@std/time.ms",
)

// Parks at the bottom of a recursion deep enough to leave the task's first stack slot, with a
// heap value in every frame, so cancelling it unwinds across grown segments (`make leak-check`
// reports any block the unwind leaves behind).
fn descend(n: Int) Int!:
	label := "frame {n}"
	parts := [label.clone(), "x"]
	if n == 0:
		sleep(seconds(600)).wait()?

	below := descend(n - 1)?
	return ok(below + parts.length())

fn main() Unit:
	deep := promise(fn: descend(20000))
	_ := sleep(milliseconds(200)).wait()
	deep.cancel()
	print("{deep.wait().is_error()}")

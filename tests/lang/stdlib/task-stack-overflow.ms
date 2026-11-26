// conform: tags=stdlib-promise,tier-io
// conform: phase=run
// A runaway recursion in a task ends the program: growth stops at 256 MiB with the
// stack overflow report.
import Placement, PromiseOptions, promise from "@std/concurrency/promise.ms"

fn forever(n Int) Int {
	return forever(n + 1) + 1
}

fn main() Int {
	p := promise(
		() => ok(forever(0)),
		options: PromiseOptions(placement: Placement.Here),
	)
	return p.wait().get_or(0)
}
// expect-exit: 139
// expect-stderr: stack overflow: call depth limit exceeded (recursion too deep or stack frames too large); check the recursion for a missing base case, or iterate instead
// expect-stderr:   at task-stack-overflow.ms:8 in forever
// expect-stderr:   ... previous frame repeated <COUNT> more times

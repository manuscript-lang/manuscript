// conform: tags=scope-cleanup,tier-core
// conform: phase=run
// A resource field leaves a mutable holder for one statement when the next statement
// refills it, so `end` closes one half of a holder and the other half stays usable.
import Closeable from "@std/core.ms"

type Half {
	id Int
	done Bool = false
}

fn move Half.close() Void! {
	if not self.done { print(f"close {self.id}") }
}

type Pair {
	first Half
	second Half
}

fn var Pair.end_first() Void! {
	half := self.first
	self.first = Half(0, done: true)
	return half.close()
}

export fn main() Void! {
	var pair = Pair(Half(1), Half(2))
	pair.end_first()?
	print("first ended")
	print(f"second {pair.second.id}")
}
// expect-exit: 0
// expect-stdout: close 1
// expect-stdout: first ended
// expect-stdout: second 2
// expect-stdout: close 2

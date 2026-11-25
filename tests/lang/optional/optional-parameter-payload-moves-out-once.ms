// conform: tags=scope-cleanup,optional,tier-core
// conform: phase=run
// `get` at the last use of an `Optional` parameter whose payload has no copy takes the payload out:
// the parameter's one owner hands it over, so the resource closes once, in the caller.
import panic from "@std/core.ms"

type Handle {
	id Int
	note String
}

fn move Handle.close() Void! {
	print(f"close {self.id}")
}

fn take(move o Handle?) Handle {
	return o or panic("called Optional.get() on null")
}

fn first[T](move value T?) T {
	return value or panic("called Optional.get() on null")
}

fn main() Void {
	h := take(Handle(1, "a"))
	print(f"got {h.id}")

	g := first[Handle](Handle(2, "b"))
	print(f"got {g.id}")
	print(first[Int](3))
}
// expect-exit: 0
// expect-stdout: got 1
// expect-stdout: got 2
// expect-stdout: 3
// expect-stdout: close 2
// expect-stdout: close 1

// expect-stdout: close one
// expect-stdout: close two
// expect-stdout: waited: true
// A guarded task faults after moving a resource field: the cleanup stack closes the
// moved door through its new owner and the other one through the record, once each.
import (
	promise from "@std/concurrency/promise.ms",
	Closeable, panic from "@std/core.ms",
	stdout from "@std/io/io.ms",
)

type Door {
	name String
}

fn move Door.close() Void! {
	stdout().write(f"close {self.name}\n").get()
}

type Room {
	first Door
	second Door
}

fn faulting() Void {
	r := Room(Door("one"), Door("two"))
	var xs List[Door] = []
	xs.append(r.first)
	panic("fault after the move")
}

fn main() Void {
	work := promise(() => ok(faulting()))
	waited := work.wait()
	stdout().write(f"waited: {waited.is_error()}\n").get()
}

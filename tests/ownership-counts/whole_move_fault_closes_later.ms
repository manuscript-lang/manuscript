// expect-stdout: close b expect-stdout: close a expect-stdout: waited: true A guarded
// task faults after moving one resource: the cleanup stack still closes the binding
// registered after it.
import (
	promise from "@std/concurrency/promise.ms",
	Closeable, panic from "@std/core.ms",
	stdout from "@std/io/io.ms",
)

type Door:
	name: String

impl Closeable for Door:
	var fn close() Unit!:
		stdout().write("close {self.name}\n").get()

fn faulting() Unit:
	var xs: List[Door] = []
	a := Door("a")
	b := Door("b")
	xs.append(a)

	_n := b.name.length()
	panic("fault after the move")

fn main() Unit:
	work := promise(fn: ok(faulting()))
	waited := work.wait()
	stdout().write("waited: {waited.is_error()}\n").get()

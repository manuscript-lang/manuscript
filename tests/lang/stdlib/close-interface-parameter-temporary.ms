// conform: tags=scope-cleanup,interfaces,tier-io
// conform: phase=run
// conform: origin=close-matrix
import Closeable from "@std/core.ms"

// A temporary passed to a `Closeable` interface parameter is a resource the interface
// value owns: the call borrows it and the statement end closes it once, however the
// call ends.
type Door {
	name String
}

fn move Door.close() Void! {
	print(f"closed {self.name}")
}

fn fails() Int! {
	return error(Error("later argument"))
}

fn look(c Closeable) Void {
	return
}

fn look_later(c Closeable, n Int) Void {
	return
}

fn attempt() Void! {
	look(Door("direct"))
	look_later(Door("later"), fails()?)
}

fn main() Void {
	void attempt()
	print("end")
}

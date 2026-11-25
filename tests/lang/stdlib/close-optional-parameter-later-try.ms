// conform: tags=scope-cleanup,generics,tier-io
// conform: phase=run
// conform: origin=close-matrix
import Closeable from "@std/core.ms"

// A temporary converted to an `Optional` parameter stays owned while a later argument's
// `try` fails: the resource closes once on that error path.
type Door {
	name String
}

fn move Door.close() Void! {
	print(f"closed {self.name}")
}

fn fails() Int! {
	return error(Error("later argument"))
}

fn take(n Int, door Door?) Void {
	return
}

fn attempt() Void! {
	take(door: Door("temp"), n: fails()?)
}

fn main() Void {
	void attempt()
	print("end")
}

// conform: tags=scope-cleanup,tier-core
// conform: phase=check
// A method value over a method that moves its receiver is accepted: the value is shared
// like any function value, and the receiver is handed over when it is made.
import Closeable, print from "@std/core.ms"

type Marker {
	id Int
}

fn move Marker.close() Void! {
	print("closed")
}

fn Marker.finish(flag Bool) Marker? {
	if flag { return null }
	return self
}

fn run() Void {
	held := Marker(1)
	f := held.finish
	r := f(false)
	print(f"{(r != null)}")
}

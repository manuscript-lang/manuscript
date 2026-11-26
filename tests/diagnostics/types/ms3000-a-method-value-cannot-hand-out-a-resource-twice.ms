// conform: tags=diagnostics
// conform: phase=check
// A method value over a method that answers a view of a resource that cannot be cloned is rejected: the value can be
// called twice, and the second call would hand out a second owner of the same resource.
import Closeable, print from "@std/core.ms"

type Marker {
	id Int
}

fn move Marker.close() Void! {
	print("closed")
}

fn hold Marker.finish(flag Bool) &Marker? {
	if flag { return null }
	return self
}

fn run() Void {
	held := Marker(1)
	f := held.finish
	r := f(false)
	print(f"{(r != null)}")
}
// expect-error: MS3000 22:15 a method that consumes a resource or answers a view of it cannot be used as a value, since the value could be called twice; call the method directly

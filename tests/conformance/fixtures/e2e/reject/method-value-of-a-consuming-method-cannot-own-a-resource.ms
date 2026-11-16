// conform: tags=scope-cleanup,tier-core
// conform: phase=check
// A method value over a method that moves its receiver would move it on every call.
// The variable and the result would both close the resource, so the value is rejected;
// call the method, or write a closure.
import Closeable, print from "@std/core.ms"

type Marker:
	id: Int

fn var Marker.close() Void!:
	print("closed")

fn Marker.finish(flag: Bool) Marker?:
	if flag: return none
	return self

fn run() Void:
	held := Marker(1)
	f := held.finish
	r := f(false)
	print(f"{r.is_some()}")

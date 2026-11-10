// expect-stdout: value 5
// expect-stdout: still present true
// expect-stdout: after inspect
// expect-stdout: original present true
// expect-stdout: close 5
import Closeable, print from "@std/core.ms"

type Marker:
	id: Int

impl Closeable for Marker:
	var fn close() Unit!:
		print("close {self.id}")

fn inspect(value: Marker?) Unit:
	print("value {value.get().id}")
	print("still present {value.is_some()}")

fn main() Unit:
	value: Marker? = Marker(5)
	inspect(value)
	print("after inspect")
	print("original present {value.is_some()}")

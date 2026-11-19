// expect-stdout: value 5
// expect-stdout: still present true
// expect-stdout: after inspect
// expect-stdout: original present true
// expect-stdout: close 5
import Closeable, print from "@std/core.ms"

type Marker:
	id: Int

fn move Marker.close() Void!:
	print(f"close {self.id}")

fn inspect(value: Marker?) Void:
	print(f"value {value.get().id}")
	print(f"still present {value.is_some()}")

fn main() Void:
	value: Marker? := Marker(5)
	inspect(value)
	print("after inspect")
	print(f"original present {value.is_some()}")

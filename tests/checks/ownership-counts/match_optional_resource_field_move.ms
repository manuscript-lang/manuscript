// expect-stdout: moved 7
// expect-stdout: closed 7
// A last-use match over an optional record moves a resource field out of the payload it
// binds: the field's new owner closes it once, and the leftover of the record (nothing
// here) closes with the arm.
import Closeable from "@std/core.ms"

type Door:
	id Int

fn move Door.close() Void!:
	print(f"closed {self.id}")

type Slot[V]:
	value V

fn take[V](move taken Slot[V]?) V!:
	match taken:
		null: return error(Error("gone"))
		slot: return ok(slot.value)

fn main() Void:
	_door := take(Slot(Door(7)))
	print("moved 7")

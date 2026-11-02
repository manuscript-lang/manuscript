# expect-debug: allocs=17 alloc_bytes=1605
# expect-release: allocs=10 alloc_bytes=1099
# expect-stdout: resource reads passed
# Read-only traversals of a mutable resource list borrow its caller-owned slot.
# The allocation expectations pin the absence of hidden list and payload copies.
import Closeable from "@std/core.ms"
import stdout from "@std/io/io.ms"

type Door:
    name: String

impl Closeable for Door:
    var fn close() Unit!:
        return ok(unit)

fn inspect(var doors: List[Door]) Int:
    doors.append(Door("second resource payload ".repeat(8).get()))
    if doors.keys() != [0, 1]: return 1
    if doors.count(fn door: door.name.byte_length() > 0) != 2: return 2
    if not doors.all(fn door: door.name.byte_length() > 0): return 3
    if not doors.any(fn door: door.name.byte_length() > 0): return 4

    var observed = 0
    doors.for_each(fn door: observed += door.name.byte_length())

    let lengths = doors.map(fn door: door.name.byte_length())
    if lengths.length() != 2: return 5

    return if observed == lengths[0] + lengths[1]: 0 else: 6

export fn main() Int:
    var doors = [Door("first resource payload ".repeat(8).get())]
    let result = inspect(var doors)
    if result != 0: return result

    stdout().write("resource reads passed\n").get()
    return 0

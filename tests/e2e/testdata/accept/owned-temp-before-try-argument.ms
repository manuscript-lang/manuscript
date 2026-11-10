import Closeable from "@std/core.ms"
import expect_equal from "@std/test/test.ms"

// A temporary that owns a resource, followed by a `try` in a later argument of the same call, is moved into the
// consumed parameter rather than copied.
interface Gate:
    var fn put(value: Int) Unit!
    var fn close() Unit!

type Door:
    unused: Bool = false

impl Gate for Door:
    var fn put(value: Int) Unit!:
        return ok(unit)

    var fn close() Unit!:
        return ok(unit)

type Holder:
    gate: Gate

impl Closeable for Holder:
    var fn close() Unit!:
        return self.gate.close()

fn make() Holder!:
    return ok(Holder(Door()))

fn both(first: Holder, second: Holder) Int!:
    var a = first
    var b = second
    try a.gate.put(1)
    try b.gate.put(2)
    return ok(2)

test "a held temporary is consumed by the call":
    count := try both(Holder(Door()), try make())
    try expect_equal(count, 2)

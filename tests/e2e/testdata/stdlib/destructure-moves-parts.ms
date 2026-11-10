import (
    Source, ReadStream from "@std/io/io.ms",
    expect_equal from "@std/test/test.ms",
)

// Destructuring a record or a list at its last use moves the parts out of it: a stream bound
// by a record pattern keeps its cell (#2430), and the parts the pattern leaves out are dropped.
type Count:
    n: Int

impl Source[Int] for Count:
    var fn next() Int?!:
        self.n += 1
        if self.n > 3: return ok(none)

        return ok(self.n)

    var fn close() Unit!:
        return ok(unit)

type Box:
    label: Int
    body: ReadStream[Int]
    spare: ReadStream[Int]

test "a record pattern moves a stream field out of its record":
    b := Box(
        label: 1, body: ReadStream[Int](Count(0)), spare: ReadStream[Int](Count(10))
    )
    var {label: _l, body: p} = b
    a := try p.next()
    try expect_equal(a, 1)

test "a record pattern over a temporary moves its fields":
    var {body: p} = Box(
        label: 2, body: ReadStream[Int](Count(0)), spare: ReadStream[Int](Count(10))
    )
    a := try p.next()
    try expect_equal(a, 1)

test "a list pattern moves its elements":
    streams := [ReadStream[Int](Count(0)), ReadStream[Int](Count(1))]
    var [first, second] = streams
    a := try first.next()
    b := try second.next()
    try expect_equal(a, 1)
    try expect_equal(b, 2)

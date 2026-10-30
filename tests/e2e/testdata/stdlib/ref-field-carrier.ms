import expect_equal from "@std/test.ms"
import Deque from "@std/deque.ms"

# A `ref` field holds a borrow of its source: nothing is copied, and the source stays unchanged
# while the carrier is in use.
type Cursor[T]:
    source: ref Deque[T]
    position: Int

impl Cursor[T]:
    var fn next() ref T?:
        let item = self.source.at(self.position)
        self.position += 1
        return item

fn cursor_of[T](d: Deque[T]) Cursor[T]:
    return Cursor(source: d, position: 0)

test "a carrier lends items from its source":
    var d = Deque[String]()
    d.push_back("a")
    d.push_back("bb")

    var it = cursor_of(d)
    var total = 0

    while true:
        if let item = it.next():
            total += item.length()
        else:
            break

    try expect_equal(total, 3)
    try expect_equal(d.length(), 2)

test "two items can be live while the cursor advances":
    var d = Deque[String]()
    d.push_back("ab")
    d.push_back("cde")

    var it = cursor_of(d)
    var n = 0
    if let a = it.next():
        if let b = it.next():
            n = a.length() + b.length()
    try expect_equal(n, 5)

fn advanced(d: Deque[String]) Cursor[String]:
    var it = cursor_of(d)
    it.position = 1
    return it

test "a carrier moves to a new variable, is returned from parameters and clones":
    var d = Deque[String]()
    d.push_back("a")
    d.push_back("bb")
    d.push_back("ccc")

    let first = advanced(d)
    var moved = first
    let copy = moved.clone()
    var total = 0

    while true:
        if let item = moved.next():
            total += item.length()
        else:
            break

    try expect_equal(total, 5)
    try expect_equal(copy.position, 1)

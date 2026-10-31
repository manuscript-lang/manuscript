import expect_equal, expect_false from "@std/test.ms"

interface Read[V]:
    fn get() V

interface Same[V: Equal]:
    fn same(other: V) Bool

type Box[T: Clonable]:
    value: T

impl Read[T] for Box[T]:
    fn get() T:
        return self.value.clone()

impl Same[T] for Box[T]:
    fn same(other: T) Bool:
        return self.value == other

type Matching[T: Equal]:
    value: T

impl Same[T] for Matching[T]:
    fn same(other: T) Bool:
        return self.value == other

type Pair[A, B: Read[A]]:
    left: A
    right: B

impl Read[Int] for Pair[Int, B]:
    fn get() Int:
        return self.right.get()

fn identity(value: Int) Int:
    return value

fn read[T: Clonable](box: Box[T]) T:
    return box.get()

test "parameters and bounds belong to interfaces and types":
    let value = Box(7)
    try expect_false(not (value.same(7)))
    try expect_false(not (Matching(8).same(8)))

    let pair = Pair(1, value)
    try expect_equal(pair.get(), 7)

    let callback = Box(identity)
    try expect_equal(read(callback)(9), 9)

import panic from "@std/faults.ms"

interface Read[V]:
    fn get() V

interface Same[V: Equal]:
    fn same(other: V) Bool

type Box[T]:
    value: T

impl Read[T] for Box[T]:
    fn get() T:
        return self.value

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

fn read[T](box: Box[T]) T:
    return box.get()

test "parameters and bounds belong to interfaces and types":
    let value = Box(7)
    if not (Same[Int](value).same(other: 7)):
        return panic(message: "check failed")
    if not (Matching(8).same(other: 8)):
        return panic(message: "check failed")

    let pair = Pair(left: 1, right: value)
    if not (pair.get() == 7):
        return panic(message: "check failed")

    let callback = Box(identity)
    if not (read(box: callback)(value: 9) == 9):
        return panic(message: "check failed")

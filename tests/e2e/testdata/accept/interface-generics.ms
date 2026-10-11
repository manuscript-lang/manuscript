interface Read[V]:
    fn get() -> V

interface Same[V: Equal]:
    fn same(other: V) -> Bool

type Box[T]:
    value: T

impl Read[T] for Box[T]:
    fn get() -> T:
        return self.value

impl Same[T] for Box[T]:
    fn same(other: T) -> Bool:
        return self.value == other

type Comparable[T: Equal]:
    value: T

impl Same[T] for Comparable[T]:
    fn same(other: T) -> Bool:
        return self.value == other

type Pair[A, B: Read[A]]:
    left: A
    right: B

impl Read[Int] for Pair[Int, B]:
    fn get() -> Int:
        return self.right.get()

fn identity(value: Int) -> Int:
    return value

fn read[T](box: Box[T]) -> T:
    return box.get()

test "parameters and bounds belong to interfaces and types":
    let value = Box(value: 7)
    assert Same[Int](value: value).same(other: 7)
    assert Comparable(value: 8).same(other: 8)
    let pair = Pair(left: 1, right: value)
    assert pair.get() == 7
    let callback = Box(value: identity)
    assert read(box: callback)(value: 9) == 9

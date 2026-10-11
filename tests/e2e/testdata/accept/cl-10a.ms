type ReadValue[T]:
    fn get() -> T

type SameValue[T]:
    fn same(other: T) -> Bool

type Box[T]:
    value: T

impl[T] ReadValue[T] for Box[T]:
    fn get() -> T:
        return self.value

impl[T: Equal] SameValue[T] for Box[T]:
    fn same(other: T) -> Bool:
        return self.value == other

fn compare[T: Equal](box: Box[T], other: T) -> Bool:
    return box.same(other: other)

test "generic implementations":
    let number = Box[Int](value: 7)
    let text = Box[String](value: "hello")
    let number_view = ReadValue[Int](value: number)
    let text_view = ReadValue[String](value: text)
    assert number_view.get() == 7
    assert text_view.get() == "hello"
    assert compare(box: number, other: 7)
    assert not compare(box: number, other: 8)

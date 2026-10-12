import panic from "@std/faults.ms"

interface ReadValue[T]:
    fn get() -> T

interface SameValue[T: Equal]:
    fn same(other: T) -> Bool

type Box[T]:
    value: T

impl ReadValue[T] for Box[T]:
    fn get() -> T:
        return self.value

impl SameValue[T] for Box[T]:
    fn same(other: T) -> Bool:
        return self.value == other

fn compare[T: Equal](box: Box[T], other: T) -> Bool:
    return box.same(other: other)

test "generic implementations":
    let number = Box[Int](value: 7)
    let text = Box[String](value: "hello")
    let number_view = ReadValue[Int](value: number)
    let text_view = ReadValue[String](value: text)
    if not (number_view.get() == 7):
        return panic(message: "check failed")
    if not (text_view.get() == "hello"):
        return panic(message: "check failed")
    if not (compare(box: number, other: 7)):
        return panic(message: "check failed")
    if not (not compare(box: number, other: 8)):
        return panic(message: "check failed")

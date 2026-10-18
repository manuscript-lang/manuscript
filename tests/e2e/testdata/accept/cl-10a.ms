import {expect_equal, expect_true} from "@std/testing.ms"

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
    let number = Box[Int](7)
    let text = Box[String]("hello")
    let number_view = ReadValue[Int](number)
    let text_view = ReadValue[String](text)
    number_view.get() | try expect_equal(expected: 7)
    text_view.get() | try expect_equal(expected: "hello")
    (compare(box: number, other: 7)) | try expect_true
    (not compare(box: number, other: 8)) | try expect_true

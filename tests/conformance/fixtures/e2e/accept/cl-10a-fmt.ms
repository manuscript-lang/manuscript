# conform: tags=control-flow,faults,formatter,generics,interfaces,modules,parser,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/cl-10a.ms
from "@std/test.ms" import expect_equal, expect_false

interface ReadValue[T]:
    def get() -> ref T

interface SameValue[T: Equal]:
    def same(other: T) -> Bool

type Box[T]:
    value: T

impl ReadValue[T] for Box[T]:
    def get() -> ref T:
        return self.value

impl SameValue[T] for Box[T]:
    def same(other: T) -> Bool:
        return self.value == other

def compare[T: Equal](box: Box[T], other: T) -> Bool:
    return box.same(other)

test "generic implementations":
    let number = Box[Int](7)
    let text = Box[String]("hello")
    let number_view: ReadValue[Int] = number
    let text_view: ReadValue[String] = text
    try expect_equal(number_view.get(), 7)
    try expect_equal(text_view.get(), "hello")
    try expect_false(not (compare(number, 7)))
    try expect_false(not (not compare(number, 8)))

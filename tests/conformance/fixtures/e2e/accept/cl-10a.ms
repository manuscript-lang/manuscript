// conform: tags=control-flow,faults,generics,interfaces,modules,records,stdlib-testing,strings,testing,tier-core,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/cl-10a.ms
import expect_equal, expect_false from "@std/test/test.ms"

interface ReadValue[T]:
    fn get() T

interface SameValue[T: Equal]:
    fn same(other: T) Bool

type Box[T: Clonable]:
    value: T

fn Box[T].get() T:
    return self.value.clone()

fn Box[T: Equal].same(other: T) Bool:
    return self.value == other

fn compare[T: Equal & Clonable](box: Box[T], other: T) Bool:
    return box.same(other)

test "generic implementations":
    number := Box[Int](7)
    text := Box[String]("hello")
    number_view: ReadValue[Int] := number
    text_view: ReadValue[String] := text
    expect_equal(number_view.get(), 7)?
    expect_equal(text_view.get(), "hello")?
    expect_false(not (compare(number, 7)))?
    expect_false(not (not compare(number, 8)))?

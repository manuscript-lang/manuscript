// conform: tags=control-flow,faults,formatter,generics,interfaces,modules,parser,records,stdlib-testing,testing,tier-core,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/interface-generics.ms
import expect_equal, expect_false from "@std/test/test.ms"

interface Read[V]:
    fn get() V

interface Same[V: Equal]:
    fn same(other: V) Bool

type Box[T]:
    value: T

fn Box[T].get() T:
    return self.value

fn Box[T: Equal].same(other: T) Bool:
    return self.value == other

type Matching[T: Equal]:
    value: T

fn Matching[T: Equal].same(other: T) Bool:
    return self.value == other

type Pair[A, B: Read[A]]:
    left: A
    right: B

fn Pair[Int, B].get() Int:
    return self.right.get()

fn identity(value: Int) Int:
    return value

fn read[T](box: Box[T]) T:
    return box.get()

test "parameters and bounds belong to interfaces and types":
    value := Box(7)
    expect_false(not (value.same(7)))?
    expect_false(not (Matching(8).same(8)))?

    pair := Pair(1, value)
    expect_equal(pair.get(), 7)?

    text := Box("seven")
    expect_equal(read(text), "seven")?

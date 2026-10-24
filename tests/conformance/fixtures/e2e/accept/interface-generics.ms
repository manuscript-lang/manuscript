# conform: tags=control-flow,faults,generics,interfaces,modules,records,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/interface-generics.ms
from "@std/testing.ms" import expect_equal, expect_false

interface Read[V]:
    def get() -> ref V

interface Same[V: Equal]:
    def same(other: V) -> Bool

type Box[T]:
    value: T

impl Read[T] for Box[T]:
    def get() -> ref T:
        return self.value

impl Same[T] for Box[T]:
    def same(other: T) -> Bool:
        return self.value == other

type Matching[T: Equal]:
    value: T

impl Same[T] for Matching[T]:
    def same(other: T) -> Bool:
        return self.value == other

type Pair[A, B: Read[A]]:
    left: A
    right: B

impl Read[Int] for Pair[Int, B]:
    def get() -> Int:
        return self.right.get()

def identity(value: Int) -> Int:
    return value

def read[T](box: Box[T]) -> ref T:
    return box.get()

test "parameters and bounds belong to interfaces and types":
    let value = Box(7)
    try expect_false(not (Same[Int](value).same(7)))
    try expect_false(not (Matching(8).same(8)))

    let pair = Pair(1, value)
    try expect_equal(pair.get(), 7)

    let callback = Box(identity)
    try expect_equal(read(callback)(9), 9)

# conform: tags=generics,lists,modules,optional,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/default-type-arguments.ms
from "@std/testing.ms" import expect_equal, expect_false

type Box[T, U = T]:
    first: T
    second: U

def pick[T = Int](values: List[T]) -> Int:
    return values.length()

def make[T = String]() -> Optional[T]:
    return none

def pair[A, B = A](first: A, second: B) -> Box[A, B]:
    return Box[A, B](first, second)

test "omitted trailing type arguments use their defaults":
    let same: Box[Int] = Box[Int](1, 2)
    let mixed: Box[Int, String] = Box[Int, String](1, "x")
    try expect_equal(same.second, 2)
    try expect_equal(mixed.second, "x")

test "constructors fall back to defaults":
    let b = Box[Int](3, 4)
    try expect_equal(b.first + b.second, 7)

test "calls infer first and only then use the default":
    let inferred = make()
    try expect_false(not (inferred.is_none()))

    let explicit: Optional[Int] = make()
    try expect_false(not (explicit.is_none()))
    try expect_equal(pick([1, 2, 3]), 3)
    try expect_equal(pair(1, "a").second, "a")

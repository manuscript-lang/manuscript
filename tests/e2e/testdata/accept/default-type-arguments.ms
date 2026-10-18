import {expect_equal, expect_true} from "@std/testing.ms"

type Box[T, U = T]:
    first: T
    second: U

fn pick[T = Int](values: List[T]) -> Int:
    return values.length()

fn make[T = String]() -> Optional[T]:
    return none

fn pair[A, B = A](first: A, second: B) -> Box[A, B]:
    return Box[A, B](first, second)

test "omitted trailing type arguments use their defaults":
    let same: Box[Int] = Box[Int](1, 2)
    let mixed: Box[Int, String] = Box[Int, String](1, "x")
    same.second | try expect_equal(expected: 2)
    mixed.second | try expect_equal(expected: "x")

test "constructors fall back to defaults":
    let b = Box[Int](first: 3, second: 4)
    (b.first + b.second) | try expect_equal(expected: 7)

test "calls infer first and only then use the default":
    let inferred = make()
    (inferred.is_none()) | try expect_true
    let explicit: Optional[Int] = make()
    (explicit.is_none()) | try expect_true
    pick([1, 2, 3]) | try expect_equal(expected: 3)
    pair(1, "a").second | try expect_equal(expected: "a")

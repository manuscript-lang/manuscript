import {expect_equal, expect_true} from "@std/testing.ms"

type Box[T]:
    v: T
    n: Int

type Pair[A, B]:
    first: A
    second: B

fn wrap[T](value: T) -> Box[T]:
    return Box[T](v: value, n: 1)

fn unwrap[T](b: Box[T]) -> T:
    return b.v

fn bump(b: Box[Int]) -> Int:
    return b.v + b.n

test "generic records":
    let a = Box[Int](v: 4, n: 2)
    (a.v == 4 and a.n == 2) | try expect_true
    let dyn = wrap(value: 7)
    bump(b: dyn) | try expect_equal(expected: 8)
    unwrap(b: a) | try expect_equal(expected: 4)
    let s = Box[String](v: "hi", n: 0)
    (s.v == "hi" and unwrap(b: s) == "hi") | try expect_true
    let nested = Box[Box[Int]](v: a, n: 3)
    (nested.v.v == 4 and nested.v == a) | try expect_true
    let items = Box[List[Int]](v: [1, 2, 3], n: 0)
    items.v.length() | try expect_equal(expected: 3)
    let pair = Pair[Int, String](first: 1, second: "x")
    (pair.first == 1 and pair.second == "x") | try expect_true
    Box[Int](v: 4, n: 2) | try expect_equal(expected: a)
    (not (Box[Int](v: 5, n: 2) == a)) | try expect_true
    let o = Box[Optional[Int]](v: some(3), n: 0)
    o.v | try expect_equal(expected: some(3))

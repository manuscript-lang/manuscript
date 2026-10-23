# conform: tags=formatter,generics,lists,modules,optional,parser,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/generic-record-instantiations-keep-semantics.ms
import {expect_true} from "@std/testing.ms"

type Box[T]:
    v: T
    n: Int

type Pair[A, B]:
    first: A
    second: B

fn wrap[T](value: T) Box[T]:
    return Box[T](v: value, n: 1)

fn unwrap[T](b: Box[T]) T:
    return b.v

fn bump(b: Box[Int]) Int:
    return b.v + b.n

test "generic records":
    let a = Box[Int](v: 4, n: 2)
    try expect_true((a.v == 4 and a.n == 2))

    let dyn = wrap(value: 7)
    try expect_true((bump(b: dyn) == 8))
    try expect_true((unwrap(b: a) == 4))

    let s = Box[String](v: "hi", n: 0)
    try expect_true((s.v == "hi" and unwrap(b: s) == "hi"))

    let nested = Box[Box[Int]](v: a, n: 3)
    try expect_true((nested.v.v == 4 and nested.v == a))

    let items = Box[List[Int]](v: [1, 2, 3], n: 0)
    try expect_true((items.v.length() == 3))

    let pair = Pair[Int, String](first: 1, second: "x")
    try expect_true((pair.first == 1 and pair.second == "x"))
    try expect_true((Box[Int](v: 4, n: 2) == a))
    try expect_true((not (Box[Int](v: 5, n: 2) == a)))

    let o = Box[Optional[Int]](v: some(3), n: 0)
    try expect_true((o.v == some(3)))

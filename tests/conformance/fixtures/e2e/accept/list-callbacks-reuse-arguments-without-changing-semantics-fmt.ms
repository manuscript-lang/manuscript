# conform: tags=closures,control-flow,faults,formatter,lists,modules,mutation,parser,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/list-callbacks-reuse-arguments-without-changing-semantics.ms
import {expect_true} from "@std/testing.ms"

fn keep(var list: List[fn() Int], value: Int) Unit:
    list.append(value: fn() Int: value)
    return unit

fn grow(var list: List[Int], value: Int) Int:
    list.append(value: value)
    return value

fn nested(items: List[Int]) List[Int]:
    return items.map(
        fn(value: Int) Int: (
            items.map(fn(inner: Int) Int: inner + value).length()
            + value
        )
    )

test "list callbacks":
    var items = List[Int]()
    var i = 0

    while i < 5:
        items.append(value: i)
        i = i + 1

    let doubled = items.map(fn(value: Int) Int: value * 2)
    try expect_true((doubled.get(index: 4) == 8))
    let even = items.filter(fn(value: Int) Bool: value % 2 == 0)
    try expect_true((even.length() == 3))
    try expect_true(
        (
            items.fold(
                initial: 0,
                step: fn(accumulator: Int, value: Int) Int: (
                    accumulator
                    + value
                )
            ) == 10
        )
    )
    try expect_true((items.count(predicate: fn(value: Int) Bool: value > 1) == 3))
    var retained = List[fn() Int]()
    for value in items:
        keep(list: var retained, value: value)
    let called = retained.map(fn(value: fn() Int) Int: value())
    try expect_true(
        (
            called.fold(
                initial: 0,
                step: fn(accumulator: Int, value: Int) Int: (
                    accumulator
                    + value
                )
            ) == 10
        )
    )
    var grown = List[Int]()
    grown.append(value: 1)
    grown.append(value: 2)
    var seen = List[Int]()
    for value in grown.clone():
        seen.append(value: grow(list: var grown, value: value))
    try expect_true((seen.length() == 2 and grown.length() == 4))
    try expect_true((nested(items: items).get(index: 2) == 7))

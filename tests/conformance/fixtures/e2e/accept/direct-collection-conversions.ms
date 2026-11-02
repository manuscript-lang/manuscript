# conform: tags=closures,control-flow,faults,generics,interfaces,lists,maps,match,modules,mutation,optional,records,sets,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/direct-collection-conversions.ms
import expect_equal, expect_false from "@std/test/test.ms"

fn append_generic[T](var values: List[T?], value: T) Unit:
    values.append(value)

type Failure:
    code: Int

impl Error for Failure:
    fn message() String: "failure"

test "direct append preserves checked argument conversions":
    var values: List[Int?] = []
    values.append(7)
    append_generic(var values, 8)
    values.append(none)
    try expect_false(values.get(0).get() != 7 or values.get(1).get() != 8)
    try expect_false(not values.get(2).is_none())

    var flags: List[Bool?] = []
    flags.append(false)
    try expect_false(flags.get(0).is_none() or flags.get(0).get())

    var units: List[Unit?] = []
    units.append(unit)
    try expect_false(units.get(0).is_none())

    let inner: Int? = none
    var nested: List[Int??] = []
    nested.append(inner)
    try expect_false((nested.get(0).is_none() or not nested.get(0).get().is_none()))

    var callbacks: List[(fn(Int) Int)?] = []
    callbacks.append(fn value: value + 1)
    try expect_equal(callbacks.get(0).get()(7), 8)

    var errors: List[Error] = []
    errors.append(Failure(1))
    try expect_equal(errors.get(0).message(), "failure")

    var results: List[Int!?] = []
    let failed: Int!Failure = error(Failure(2))
    results.append(failed)

    let widened = results.get(0).get()
    try expect_false(widened.is_ok())
    try expect_equal(widened.err().message(), "failure")

test "direct keyed calls preserve optional keys and values":
    var values: List[Int?] = []
    values.append(7)
    try expect_false(not values.contains(7) or values.contains(8))

    var entries = Map[Int?, Int?]()
    entries.add(7, 9)
    try expect_false(not entries.contains(7) or entries.get(7).get().get() != 9)
    entries.add(value: 10, key: 8)
    try expect_equal(entries.get(8).get().get(), 10)

    var keys = Set[Int?]()
    keys.add(7)
    keys.add(none)
    try expect_false(
        (not keys.contains(7) or not keys.contains(none) or keys.length() != 2)
    )

test "direct calls capture receiver and arguments in written order":
    let first: List[Int?] = []
    let second: List[Int?] = []
    var receiver = first.clone()
    receiver.append(
        (
            match present(7):
                value:
                    receiver = second.clone()
                    value
                none: 0
        ) + 0
    )
    try expect_false(not first.is_empty() or not second.is_empty())

    var entries = Map[Int, Int?]()
    var key = 1
    entries.add(
        key,
        (
            match present(7):
                value:
                    key = 2
                    value
                none: 0
        ) + 0
    )
    try expect_false(
        (entries.get(1).get().get() != 7 or entries.contains(2) or key != 2)
    )

fn present[T](value: T) T?:
    return value

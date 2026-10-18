import {expect_equal, expect_false, expect_true, fail} from "@std/testing.ms"

fn append_generic[T](values: List[Optional[T]], value: T) -> Unit:
    values.append(value)

type Failure:
    code: Int

impl Error for Failure:
    fn message() -> String: "failure"

test "direct append preserves checked argument conversions":
    let values: List[Optional[Int]] = []
    values.append(7)
    append_generic(values, value: 8)
    values.append(none)
    (values.at(0).unwrap().unwrap() != 7 or values.at(1).unwrap().unwrap() != 8) | try expect_false
    (values.at(2).unwrap().is_none()) | try expect_true
    let flags: List[Optional[Bool]] = []
    flags.append(false)
    (flags.at(0).unwrap().is_none() or flags.at(0).unwrap().unwrap()) | try expect_false
    let units: List[Optional[Unit]] = []
    units.append(unit)
    units.at(0).unwrap().is_none() | try expect_false
    let inner: Optional[Int] = none
    let nested: List[Optional[Optional[Int]]] = []
    nested.append(inner)
    (nested.at(0).unwrap().is_none() or not nested.at(0).unwrap().unwrap().is_none()) | try expect_false
    let callbacks: List[Optional[fn(value: Int) -> Int]] = []
    callbacks.append(fn(value): value + 1)
    callbacks.at(0).unwrap().unwrap()(7) | try expect_equal(expected: 8)
    let errors: List[Error] = []
    errors.append(Failure(1))
    errors.at(0).unwrap().message() | try expect_equal(expected: "failure")
    let results: List[Optional[Result[Int, Error]]] = []
    let failed: Result[Int, Failure] = error(Failure(2))
    results.append(failed)

    match results.at(0).unwrap().unwrap():
        ok(value): return fail("error became success")
        error(cause):
            try expect_equal(cause.message(), "failure")

test "direct keyed calls preserve optional keys and values":
    let values: List[Optional[Int]] = []
    values.append(7)
    (not values.contains(7) or values.contains(8)) | try expect_false
    let entries = Map[Optional[Int], Optional[Int]]()
    entries.add(7, 9)
    (not entries.contains(7) or entries.get(7).unwrap().unwrap() != 9) | try expect_false
    entries.add(value: 10, key: 8)
    entries.get(8).unwrap().unwrap() | try expect_equal(expected: 10)
    let keys = Set[Optional[Int]]()
    keys.add(7)
    keys.add(none)
    (not keys.contains(7) or not keys.contains(none) or keys.length() != 2) | try expect_false

test "direct calls capture receiver and arguments in written order":
    let first: List[Optional[Int]] = []
    let second: List[Optional[Int]] = []
    var receiver = first
    receiver.append(
        (
            match some(7):
                some(value):
                    receiver = second
                    value
                none: 0
        ) + 0
    )
    (first.at(0).unwrap().unwrap() != 7 or not second.is_empty()) | try expect_false
    let entries = Map[Int, Optional[Int]]()
    var key = 1
    entries.add(
        key,
        (
            match some(7):
                some(value):
                    key = 2
                    value
                none: 0
        ) + 0
    )
    (entries.get(1).unwrap().unwrap() != 7 or entries.contains(2) or key != 2) | try expect_false

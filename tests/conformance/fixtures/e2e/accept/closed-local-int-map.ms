# conform: tags=closures,control-flow,faults,lists,maps,modules,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/closed-local-int-map.ms
import {expect_contains, expect_equal, expect_false, expect_fault, expect_true} from "@std/testing.ms"

fn effect(visits: List[Int], value: Int) Int:
    visits.append(value)
    return value

fn missing() Int:
    let values = Map[Int, Int]()
    return values.get(0).get()

fn returned_alias() Map[Int, Int]:
    var values = Map[Int, Int]()
    values.add(2, 20)
    return values

test "closed maps preserve lookup replacement and absence":
    var values = Map[Int, Int]()
    values.length() | try expect_equal(expected: 0)
    values.contains(7) | try expect_false
    values.get(7).is_none() | try expect_true
    values.add(7, 10)
    values.add(7, 20)
    values.add(-1, 30)
    values.length() | try expect_equal(expected: 2)
    values.contains(7) | try expect_true
    values.get(7).get() | try expect_equal(expected: 20)
    values.get(-1).get() | try expect_equal(expected: 30)
    values.get(0).get(99) | try expect_equal(expected: 99)

test "closed map arguments retain written evaluation order":
    let visits: List[Int] = []
    var values = Map[Int, Int]()
    values.add(value: effect(visits, 20), key: effect(visits, 2))
    values.add(key: effect(visits, 3), value: effect(visits, 30))
    visits | try expect_equal(expected: [20, 2, 3, 30])
    values.get(2).get() | try expect_equal(expected: 20)
    values.get(3).get() | try expect_equal(expected: 30)

test "missing local lookups keep Optional faults":
    (try expect_fault(fn(): let ignored = missing())) | try expect_contains(
        expected: "Optional.get"
    )

test "escaped map results keep insertion order":
    var values = returned_alias()
    values.add(1, 10)
    values.add(2, 21)
    var seen: List[Int] = []
    for entry in values:
        seen.append(entry.key)
    seen | try expect_equal(expected: [2, 1])
    values.get(2).get() | try expect_equal(expected: 21)

test "captured maps read the entries present at capture":
    var values = Map[Int, Int]()
    values.add(1, 10)
    let callback = fn() Int: values.get(1).get()
    callback() | try expect_equal(expected: 10)

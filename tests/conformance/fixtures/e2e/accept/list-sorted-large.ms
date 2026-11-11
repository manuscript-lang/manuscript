// conform: tags=lists,records,strings,stdlib-testing,testing,tier-core
// conform: phase=test
// conform: origin=perf thread: List.sorted is a stable n log n sort
import expect_equal from "@std/test/test.ms"

type Entry:
    key: Int
    label: String

fn by_key(left: Entry, right: Entry) Int:
    return left.key - right.key

fn ascending(left: Int, right: Int) Int:
    return left - right

fn alphabetical(left: String, right: String) Int:
    if left < right: return -1
    if left > right: return 1

    return 0

test "sorting a large list is ordered and leaves the source unchanged":
    var values: List[Int] = []
    for i in 0..20000:
        values.append((i * 7919) % 20011)

    sorted := values.sorted(ascending)
    expect_equal(sorted.length(), 20000)?
    for i in 1..20000:
        expect_equal(sorted.get(i - 1) <= sorted.get(i), true)?
    expect_equal(values.get(1), 7919)?

test "sorting is stable for equal keys":
    var entries: List[Entry] = []
    for i in 0..1000:
        entries.append(Entry(i % 7, "e{i}"))

    sorted := entries.sorted(by_key)
    var previous = sorted.get(0).clone()

    for i in 1..1000:
        current := sorted.get(i)
        if current.key == previous.key:
            expect_equal(previous.label.length() <= current.label.length(), true)?
        previous = current.clone()

    expect_equal(sorted.get(0).label, "e0")?
    expect_equal(sorted.get(1).label, "e7")?

test "strings, empty and single element lists sort":
    words := ["pear", "apple", "fig", "banana", "apple"]
    expect_equal(
        words.sorted(alphabetical), ["apple", "apple", "banana", "fig", "pear"]
    )?

    none: List[Int] := []
    expect_equal(none.sorted(ascending), none)?
    expect_equal([5].sorted(ascending), [5])?

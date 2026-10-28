# conform: tags=aliasing,closures,control-flow,faults,formatter,generics,interpolation,lists,modules,mutation,optional,parser,records,stdlib-collections,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/stdlib/list-parity.ms
from "@std/test.ms" import expect_equal, expect_false

test "List count calls the predicate once per element":
    let values = [1, 2, 3, 4]
    var seen: List[Int] = []

    let even = values.count(
        lambda (value: Int) -> Bool:
            seen.append(value)
            return value % 2 == 0
    )

    try expect_false(even != 2 or seen != values)

    let empty: List[Int] = []
    try expect_equal(empty.count(lambda (value: Int) -> Bool: True), 0)

test "List insert mutates in place":
    var values = [1, 3]
    values.insert(1, 2)
    try expect_equal(values, [1, 2, 3])
    values.append(4)
    try expect_equal(values, [1, 2, 3, 4])
    values.insert(0, 0)
    values.insert(5, 5)
    try expect_equal(values, [0, 1, 2, 3, 4, 5])
    values.insert(-1, 9)
    try expect_equal(values, [0, 1, 2, 3, 4, 9, 5])
    values.insert(-7, 8)
    try expect_equal(values, [8, 0, 1, 2, 3, 4, 9, 5])

    var empty: List[String] = []
    empty.insert(0, "a")
    try expect_equal(empty, ["a"])

test "List pop removes and returns the last element":
    var values = [1, 2, 3]
    let last = values.pop()
    try expect_false((last != some(3) or values != [1, 2]))
    values.pop()
    values.pop()
    try expect_false(values.pop().is_some() or not (values.is_empty()))

type Box:
    value: Int

test "List pop and distinct copy payloads":
    let shared = Box(1)
    var boxes = [shared.clone()]
    let popped = boxes.pop()
    var item = popped.get().clone()
    item.value = 2
    try expect_false(shared.value != 1 or item.value != 2 or not boxes.is_empty())

    let nested = [1]
    let lists = [nested.clone(), [1], [2]]
    let unique = lists.distinct()
    var inner = unique.get(0).clone()
    inner.append(3)
    try expect_false(unique.length() != 2 or nested != [1] or inner != [1, 3])

test "List distinct keeps the first equal element in order":
    let values = [3, 1, 3, 2, 1]
    var unique = values.distinct()
    try expect_false(unique != [3, 1, 2] or values != [3, 1, 3, 2, 1])
    unique.append(4)
    try expect_equal(values.length(), 5)

    let words = ["b", "a", "b"]
    try expect_equal(words.distinct(), ["b", "a"])

    let empty: List[Int] = []
    var copy = empty.distinct()
    copy.append(1)
    try expect_false(not (empty.is_empty()))

def unique_count[T: Equal](values: List[T]) -> Int:
    return values.distinct().length()

test "List parity operations support generic and bound use":
    try expect_equal(unique_count([1, 1, 2]), 2)

    var values = [1, 2]
    let insert = values.insert
    let pop: Callable[[], Optional[Int]] = values.pop
    let count = values.count
    insert(2, 3)
    try expect_false(
        pop() != some(3) or count(lambda (value: Int) -> Bool: value > 0) != 2
    )

test "List distinct handles large Int and String lists":
    var numbers: List[Int] = []
    var words: List[String] = []

    for index in 0..60000:
        numbers.append(index % 30000)
        words.append(f"w{index % 20000}")

    let unique = numbers.distinct()
    try expect_false(
        (
            unique.length() != 30000
            or unique.first() != some(0)
            or unique.last() != some(29999)
        )
    )

    let uniqueWords = words.distinct()
    try expect_false(uniqueWords.length() != 20000 or uniqueWords.get(1) != "w1")

import {expect_equal, expect_false, expect_not_equal, fail} from "@std/testing.ms"
import range from "@std/collections.ms"

interface Counter:
    var fn increment() Unit

type Val:
    val: Int

impl Counter for Val:
    var fn increment() Unit:
        self.val += 1

type Box[T]:
    value: T
    child: Val

fn replace[T](var box: Box[T], value: T) Unit:
    box.value = value

fn receiver(var log: List[Int], value: Val) Val:
    log.append(1)
    return value

fn replacement(var log: List[Int]) Int:
    log.append(2)
    return 7

fn bump(var value: Val) Unit:
    value.val += 1

test "record fields mutate through methods views and var parameters":
    var counter = Val(0)
    let copy = counter.clone()
    counter.increment()

    var view = Counter(counter.clone())
    view.increment()

    let increment = counter.increment
    increment()
    bump(var counter)
    try expect_false(not (counter.val == 3 and copy.val == 0))

    var box = Box("old", counter.clone())
    var copied = box.clone()
    replace(var box, "new")
    copied.child.val = 9
    try expect_equal(box.value, "new")
    try expect_equal(copied.value, "old")
    try expect_equal(copied.child.val, 9)

    var log: List[Int] = []
    var target = receiver(var log, counter.clone())
    target.val = replacement(var log)
    try expect_false(not (log == [1, 2] and target.val == 7 and counter.val == 3))

test "collection updates mutate in place and clone separates storage":
    var values = [1, 2]
    let copy = values.clone()
    let append = values.append
    append(3)
    values.prepend(0)
    values.set(1, 9)
    try expect_false(not (values == [0, 9, 2, 3] and copy == [1, 2]))
    values.remove(1)
    values.reverse_in_place()
    values.fill(8, 0, 1)
    try expect_equal(values, [8, 2, 0])
    values.splice(1, 1, values.clone())
    try expect_equal(values, [8, 8, 2, 0, 0])

    var map = Map[String, Int]()
    map.add("a", 1)

    let map_copy = map.clone()
    map.add("b", 2)
    map.remove("a")
    try expect_false(not (map.keys() == ["b"] and map_copy.keys() == ["a"]))

    var set = Set[Int]([1])
    let set_copy = set.clone()
    set.add(2)
    set.remove(1)
    try expect_false(not (set.values() == [2] and set_copy.values() == [1]))

test "for loop iterates a snapshot while the source changes":
    var values = [1, 2, 3]
    var seen: List[Int] = []

    for value in values.clone():
        seen.append(value)
        values.fill(9, 0, 3)

    try expect_false(not (seen == [1, 2, 3] and values == [9, 9, 9]))

test "callbacks over a snapshot leave the source writable":
    var values = [1, 2, 3]
    let result = values.clone().map(fn(value): return value + 1)
    values.fill(9, 0, 3)
    try expect_false(not (result == [2, 3, 4] and values == [9, 9, 9]))

test "list growth and saved clone methods preserve current contents":
    var values: List[Int] = []
    for index in range(0, 2048):
        values.append(index)

    let clone = values.clone
    let copy = clone()
    values.append(2048)
    values.set(0, -1)
    try expect_false(not (values.length() == 2049 and values.last() == some(2048)))
    try expect_false(
        not (
            copy.length() == 2048
            and copy.first() == some(0)
            and copy.last() == some(2047)
        )
    )

    let empty: List[Int] = []
    var empty_copy = empty.clone()
    empty_copy.append(1)
    try expect_false(not (empty.length() == 0 and empty_copy.length() == 1))

test "collection clones keep independent lengths":
    let child = Val(1)
    let values = [child.clone()]
    var copied_values = values.clone()
    copied_values.append(Val(2))

    var entries = Map[String, Val]()
    entries.add("child", child.clone())

    var copied_entries = entries.clone()
    copied_entries.add("other", Val(3))
    try expect_false(
        not (
            values.length() == 1
            and copied_values.length() == 2
            and entries.length() == 1
            and copied_entries.length() == 2
        )
    )
    for value in values:
        try expect_equal(value.val, 1)

    if let value = entries.get("child"):
        try expect_equal(value.val, 1)
    else:
        return fail("cloning removed an original map entry")

test "map and set clear affect their owner while copies retain contents":
    var entries = Map[String, Int]()
    entries.add("a", 1)

    let copy = entries.clone()
    let update = entries.add
    update("a", 2)

    var chain_1 = Map[String, Int]()
    chain_1.add("b", 3)
    entries.merge(chain_1)
    try expect_false(
        not (
            entries.keys() == ["a", "b"]
            and entries.values() == [2, 3]
            and copy.values() == [1]
        )
    )
    entries.clear()
    try expect_false(not (entries.length() == 0 and copy.length() == 1))

    var values = Set[Int]([1])
    let set_copy = values.clone()
    values.add(1)
    values.add(2)
    values.remove(9)
    try expect_false(not (values.values() == [1, 2] and set_copy.values() == [1]))
    values.clear()
    try expect_false(not (values.length() == 0 and set_copy.length() == 1))

type Choice:
    case Present(value: Val)
    case Missing

test "alternative clones retain tags and payloads":
    let child = Val(1)
    let original = Choice.Present(child)
    let copy = original.clone()

    match copy:
        Choice.Present(value):
            try expect_equal(value.val, 1)
        Choice.Missing:
            return fail("clone changed the alternative tag")

    match original:
        Choice.Present(value):
            try expect_equal(value.val, 1)
        Choice.Missing:
            return fail("clone changed the original alternative")

    let missing = Choice.Missing.clone()
    try expect_equal(missing, Choice.Missing)

type Node:
    value: Int
    children: List[Node]

test "mutable recursive graphs compare and clone without recursion failures":
    var left = Node(1, [])
    var right = Node(1, [])
    left.children.append(left.clone())
    right.children.append(right.clone())
    try expect_equal(left, right)

    var copy = left.clone()
    copy.value = 2
    try expect_false(not (left.value == 1 and left != copy))
    copy.children.append(Node(3, []))
    try expect_equal(copy.children.length(), 2)
    right.value = 4
    try expect_not_equal(left, right)

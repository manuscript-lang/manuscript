# conform: tags=aliasing,alternatives,closures,control-flow,faults,generics,interfaces,lists,maps,match,modules,optional,records,sets,stdlib-collections,stdlib-testing,strings,testing,tier-stdlib,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/mutation.ms
import {expect_equal, expect_false, expect_not_equal, fail} from "@std/testing.ms"
import range from "@std/collections.ms"

interface Counter:
    fn increment() Unit

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

test "record fields mutate through aliases methods views and captures":
    var counter = Val(0)
    let alias = counter
    let copy = counter.clone()
    counter.increment()
    let view = Counter(counter)
    view.increment()
    let increment = counter.increment
    increment()
    let callback = fn():
        counter.val += 1
    callback()
    try expect_false(not (alias.val == 4 and copy.val == 0))
    var box = Box("old", counter)
    var copied = box.clone()
    replace(var box, "new")
    copied.child.val = 9
    try expect_false(
        not (
            box.value == "new"
            and copied.value == "old"
            and box.child.val == 9
        )
    )
    var log: List[Int] = []
    receiver(log, counter).val = replacement(var log)
    try expect_false(not (log == [1, 2] and counter.val == 7))

test "collection updates retain identity and clone separates storage":
    var values = [1, 2]
    let alias = values
    let copy = values.clone()
    let append = values.append
    append(3)
    values.prepend(0)
    values.set(1, 9)
    try expect_false(not (alias == [0, 9, 2, 3] and copy == [1, 2]))
    values.remove(1)
    values.reverse_in_place()
    values.fill(8, 0, 1)
    try expect_equal(alias, [8, 2, 0])
    values.splice(1, 1, values)
    try expect_equal(alias, [8, 8, 2, 0, 0])
    var map = Map[String, Int]()
    map.add("a", 1)
    let map_alias = map
    let map_copy = map.clone()
    map.add("b", 2)
    map.remove("a")
    try expect_false(not (map_alias.keys() == ["b"] and map_copy.keys() == ["a"]))
    var set = Set[Int]([1])
    let set_alias = set
    let set_copy = set.clone()
    set.add(2)
    set.remove(1)
    try expect_false(not (set_alias.values() == [2] and set_copy.values() == [1]))

test "for loop captures length and observes backing writes":
    var values = [1, 2, 3]
    var seen: List[Int] = []

    for value in values:
        seen.append(value)
        values.fill(9, 0, 3)

    try expect_false(not (seen == [1, 9, 9] and values == [9, 9, 9]))

test "callbacks capture length while mutating their source":
    var values = [1, 2, 3]
    let result = values.map(
        fn(value):
            values.fill(9, 0, 3)
            return value + 1
    )
    try expect_false(not (result == [2, 10, 10] and values == [9, 9, 9]))

test "list growth and saved clone methods preserve current contents":
    var values: List[Int] = []
    var alias = values
    let clone = values.clone
    for index in range(0, 2048):
        values.append(index)
    let copy = clone()
    alias.append(2048)
    values.set(0, -1)
    try expect_false(not (alias.length() == 2049 and alias.last() == some(2048)))
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

test "collection clones retain nested object references":
    let child = Val(1)
    let values = [child]
    var copied_values = values.clone()
    copied_values.append(Val(2))
    var entries = Map[String, Val]()
    entries.add("child", child)
    var copied_entries = entries.clone()
    copied_entries.add("other", Val(3))
    for entry in copied_entries.entries():
        if entry.key == "child":
            entry.value.val = 7
    try expect_false(
        not (
            values.length() == 1
            and copied_values.length() == 2
            and entries.length() == 1
            and copied_entries.length() == 2
        )
    )
    for value in values:
        try expect_equal(value.val, 7)

    if let value = entries.get("child"):
        try expect_equal(value.val, 7)
    else:
        return fail("cloning removed an original map entry")

test "map and set clear affect aliases while copies retain contents":
    var entries = Map[String, Int]()
    entries.add("a", 1)
    let alias = entries
    let copy = entries.clone()
    let update = entries.add
    update("a", 2)
    var chain_1 = Map[String, Int]()
    chain_1.add("b", 3)
    entries.merge(chain_1)
    try expect_false(
        not (
            alias.keys() == ["a", "b"]
            and alias.values() == [2, 3]
            and copy.values() == [1]
        )
    )
    entries.clear()
    try expect_false(not (alias.length() == 0 and copy.length() == 1))
    var values = Set[Int]([1])
    let set_alias = values
    let set_copy = values.clone()
    values.add(1)
    values.add(2)
    values.remove(9)
    try expect_false(not (set_alias.values() == [1, 2] and set_copy.values() == [1]))
    values.clear()
    try expect_false(not (set_alias.length() == 0 and set_copy.length() == 1))

type Choice:
    case Present(value: Val)
    case Missing

test "alternative clones retain tags and shared payload references":
    let child = Val(1)
    let original = Choice.Present(child)
    let copy = original.clone()

    match copy:
        Choice.Present(value):
            value.val = 9
        Choice.Missing:
            return fail("clone changed the alternative tag")

    match original:
        Choice.Present(value):
            try expect_equal(value.val, 9)
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
    left.children.append(left)
    right.children.append(right)
    try expect_equal(left, right)
    var copy = left.clone()
    copy.value = 2
    try expect_false(not (left.value == 1 and left != copy))
    copy.children.append(Node(3, []))
    try expect_equal(left.children.length(), 2)
    right.value = 4
    try expect_not_equal(left, right)

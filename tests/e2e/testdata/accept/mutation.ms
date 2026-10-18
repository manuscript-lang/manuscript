import {expect_equal, expect_false, expect_not_equal, expect_true, fail} from "@std/testing.ms"
import Synchronized from "@std/sync.ms"
import TaskGroup from "@std/tasks.ms"

interface Counter:
    fn increment() -> Unit

type Val:
    val: Int

impl Counter for Val:
    fn increment() -> Unit:
        self.val = self.val + 1

type Box[T]:
    value: T
    child: Val

fn replace[T](box: Box[T], value: T) -> Unit:
    box.value = value

fn receiver(log: List[Int], value: Val) -> Val:
    log.append(1)
    return value

fn replacement(log: List[Int]) -> Int:
    log.append(2)
    return 7

test "record fields mutate through aliases methods views and captures":
    let counter = Val(0)
    let alias = counter
    let copy = counter.clone()
    counter.increment()
    let view = Counter(counter)
    view.increment()
    let increment = counter.increment
    increment()
    let callback = fn():
        counter.val = counter.val + 1
    callback()
    (alias.val == 4 and copy.val == 0) | try expect_true
    let box = Box(value: "old", child: counter)
    let copied = box.clone()
    replace(box: box, value: "new")
    copied.child.val = 9
    ((box.value == "new" and copied.value == "old" and box.child.val == 9)) | try expect_true
    let log: List[Int] = []
    receiver(log: log, value: counter).val = replacement(log)
    (log == [1, 2] and counter.val == 7) | try expect_true

test "collection updates retain identity and clone separates storage":
    let values = [1, 2]
    let alias = values
    let copy = values.clone()
    let append = values.append
    append(3)
    values.prepend(0).set(index: 1, value: 9)
    (alias == [0, 9, 2, 3] and copy == [1, 2]) | try expect_true
    values.remove(1).reverse_in_place().fill(value: 8, start: 0, end: 1)
    alias | try expect_equal(expected: [8, 2, 0])
    values.splice(start: 1, delete_count: 1, replacement: values)
    alias | try expect_equal(expected: [8, 8, 2, 0, 0])
    let map = Map[String, Int]().add(key: "a", value: 1)
    let map_alias = map
    let map_copy = map.clone()
    map.add(key: "b", value: 2).remove("a")
    (map_alias.keys() == ["b"] and map_copy.keys() == ["a"]) | try expect_true
    let set = Set[Int]().add(1)
    let set_alias = set
    let set_copy = set.clone()
    set.add(2).remove(1)
    (set_alias.values() == [2] and set_copy.values() == [1]) | try expect_true

test "for loop captures length and observes backing writes":
    let values = [1, 2, 3]
    let seen: List[Int] = []

    for value in values:
        seen.append(value)
        values.fill(value: 9, start: 0, end: 3)

    (seen == [1, 9, 9] and values == [9, 9, 9]) | try expect_true

test "Synchronized protects record mutation without replacement":
    let counter = Synchronized(Val(0))
    let operation = fn():
        var remaining = 100

        while remaining > 0:
            with guard = counter.lock():
                guard.get().increment()
            remaining = remaining - 1

    with group = TaskGroup():
        group.start(operation)
        group.start(operation)
        group.start(operation)
        group.start(operation)

        match group.join():
            ok(_):
                with guard = counter.lock():
                    guard.get().val | try expect_equal(expected: 400)
            error(_):
                return fail(message: "task mutation failed")

test "callbacks capture length while mutating their source":
    let values = [1, 2, 3]
    let result = values.map(
        fn(value):
            values.fill(value: 9, start: 0, end: 3)
            return value + 1
    )
    (result == [2, 10, 10] and values == [9, 9, 9]) | try expect_true

test "list growth and saved clone methods preserve current contents":
    let values: List[Int] = []
    let alias = values
    let clone = values.clone
    var index = 0

    while index < 2048:
        values.append(index)
        index = index + 1

    let copy = clone()
    alias.append(2048)
    values.set(index: 0, value: -1)
    (alias.length() == 2049 and alias.last() == some(2048)) | try expect_true
    (
        not (
            copy.length() == 2048
            and copy.first() == some(0)
            and copy.last() == some(2047)
        )
    ) | try expect_false
    let empty: List[Int] = []
    let empty_copy = empty.clone()
    empty_copy.append(1)
    (empty.length() == 0 and empty_copy.length() == 1) | try expect_true

test "collection clones retain nested object references":
    let child = Val(1)
    let values = [child]
    let copied_values = values.clone()
    copied_values.append(Val(2))
    let entries = Map[String, Val]().add(key: "child", value: child)
    let copied_entries = entries.clone()
    copied_entries.add(key: "other", value: Val(3))
    for entry in copied_entries.entries():
        if entry.key == "child":
            entry.value.val = 7
    (
        not (
            values.length() == 1
            and copied_values.length() == 2
            and entries.length() == 1
            and copied_entries.length() == 2
        )
    ) | try expect_false
    for value in values:
        value.val | try expect_equal(expected: 7)

    match entries.get("child"):
        some(value):
            try expect_equal(value.val, 7)
        none:
            return fail(message: "cloning removed an original map entry")

test "map and set clear affect aliases while copies retain contents":
    let entries = Map[String, Int]().add(key: "a", value: 1)
    let alias = entries
    let copy = entries.clone()
    let update = entries.add
    update(key: "a", value: 2)
    entries.merge(Map[String, Int]().add(key: "b", value: 3))
    (
        not (
            alias.keys() == ["a", "b"]
            and alias.values() == [2, 3]
            and copy.values() == [1]
        )
    ) | try expect_false
    entries.clear()
    (alias.length() == 0 and copy.length() == 1) | try expect_true
    let values = Set[Int]().add(1)
    let set_alias = values
    let set_copy = values.clone()
    values.add(1).add(2).remove(9)
    (set_alias.values() == [1, 2] and set_copy.values() == [1]) | try expect_true
    values.clear()
    (set_alias.length() == 0 and set_copy.length() == 1) | try expect_true

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
            return fail(message: "clone changed the alternative tag")

    match original:
        Choice.Present(value):
            try expect_equal(value.val, 9)
        Choice.Missing:
            return fail(message: "clone changed the original alternative")

    let missing = Choice.Missing.clone()
    missing | try expect_equal(expected: Choice.Missing)

type Node:
    value: Int
    children: List[Node]

test "mutable recursive graphs compare and clone without recursion failures":
    let left = Node(value: 1, children: [])
    let right = Node(value: 1, children: [])
    left.children.append(left)
    right.children.append(right)
    left | try expect_equal(expected: right)
    let copy = left.clone()
    copy.value = 2
    (left.value == 1 and left != copy) | try expect_true
    copy.children.append(Node(value: 3, children: []))
    left.children.length() | try expect_equal(expected: 2)
    right.value = 4
    left | try expect_not_equal(expected: right)

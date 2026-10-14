import List from "@std/collections.ms"
import Map from "@std/collections.ms"
import Set from "@std/collections.ms"
import Optional from "@std/optional.ms"
import Synchronized from "@std/sync.ms"
import TaskGroup from "@std/tasks.ms"
import panic from "@std/faults.ms"

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
    if not (alias.val == 4 and copy.val == 0):
        return panic(message: "counter alias or clone failed")

    let box = Box(value: "old", child: counter)
    let copied = box.clone()
    replace(box: box, value: "new")
    copied.child.val = 9
    if not (
        box.value == "new"
        and copied.value == "old"
        and box.child.val == 9
    ):
        return panic(message: "clones must be shallow")

    let log: List[Int] = []
    receiver(log: log, value: counter).val = replacement(log)
    if not (log == [1, 2] and counter.val == 7):
        return panic(message: "assignment must evaluate receiver once before value")

test "collection updates retain identity and clone separates storage":
    let values = [1, 2]
    let alias = values
    let copy = values.clone()
    let append = values.append
    append(3)
    values.prepend(0).set(index: 1, value: 9)
    if not (alias == [0, 9, 2, 3] and copy == [1, 2]):
        return panic(message: "list aliases lost storage or length")

    values.remove(1).reverse_in_place().fill(value: 8, start: 0, end: 1)
    if not (alias == [8, 2, 0]):
        return panic(message: "list updates must mutate")

    values.splice(start: 1, delete_count: 1, replacement: values)
    if not (
        alias == [
            8,
            8,
            2,
            0,
            0
        ]
    ):
        return panic(message: "self replacement failed")

    let map = Map[String, Int]().add(key: "a", value: 1)
    let map_alias = map
    let map_copy = map.clone()
    map.add(key: "b", value: 2).remove("a")
    if not (map_alias.keys() == ["b"] and map_copy.keys() == ["a"]):
        return panic(message: "map aliases or clone failed")

    let set = Set[Int]().add(1)
    let set_alias = set
    let set_copy = set.clone()
    set.add(2).remove(1)
    if not (set_alias.values() == [2] and set_copy.values() == [1]):
        return panic(message: "set aliases or clone failed")

test "for loop captures length and observes backing writes":
    let values = [1, 2, 3]
    let seen: List[Int] = []

    for value in values:
        seen.append(value)
        values.fill(value: 9, start: 0, end: 3)

    if not (seen == [1, 9, 9] and values == [9, 9, 9]):
        return panic("range did not observe backing writes")

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
                    if not (guard.get().val == 400):
                        return panic(message: "synchronized mutation lost updates")

            error(_):
                return panic(message: "task mutation failed")

test "callbacks capture length while mutating their source":
    let values = [1, 2, 3]
    let result = values.map(
        fn(value):
            values.fill(value: 9, start: 0, end: 3)
            return value + 1
    )
    if not (result == [2, 10, 10] and values == [9, 9, 9]):
        return panic("callback copied backing membership")

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
    if not (alias.length() == 2049 and alias.last() == some(2048)):
        return panic(message: "growth lost the aliased collection header")
    if not (
        copy.length() == 2048
        and copy.first() == some(0)
        and copy.last() == some(2047)
    ):
        return panic(message: "saved clone method failed to separate current storage")

    let empty: List[Int] = []
    let empty_copy = empty.clone()
    empty_copy.append(1)
    if not (empty.length() == 0 and empty_copy.length() == 1):
        return panic(message: "empty clone retained mutable storage")

test "collection clones retain nested object references":
    let child = Val(1)
    let values = [child]
    let copied_values = values.clone()
    copied_values.append(Val(2))
    let entries = Map[String, Val]().add(key: "child", value: child)
    let copied_entries = entries.clone()
    copied_entries.add(
        key: "other",
        value: Val(3)
    )

    for entry in copied_entries.entries():
        if entry.key == "child":
            entry.value.val = 7

    if not (
        values.length() == 1
        and copied_values.length() == 2
        and entries.length() == 1
        and copied_entries.length() == 2
    ):
        return panic(message: "cloned collection storage was still shared")

    for value in values:
        if not (value.val == 7):
            return panic(message: "list clone unexpectedly copied nested records")

    match entries.get("child"):
        some(value):
            if not (value.val == 7):
                return panic(message: "map clone unexpectedly copied nested records")

        none:
            return panic(message: "cloning removed an original map entry")

test "map and set clear affect aliases while copies retain contents":
    let entries = Map[String, Int]().add(key: "a", value: 1)
    let alias = entries
    let copy = entries.clone()
    let update = entries.add
    update(key: "a", value: 2)
    entries.merge(Map[String, Int]().add(key: "b", value: 3))
    if not (
        alias.keys() == ["a", "b"]
        and alias.values() == [2, 3]
        and copy.values() == [1]
    ):
        return panic(message: "map replacement or merge lost identity")

    entries.clear()
    if not (alias.length() == 0 and copy.length() == 1):
        return panic(message: "map clear changed a clone or lost an alias")

    let values = Set[Int]().add(1)
    let set_alias = values
    let set_copy = values.clone()
    values.add(1).add(2).remove(9)
    if not (set_alias.values() == [1, 2] and set_copy.values() == [1]):
        return panic(message: "set duplicate or missing removal changed membership")

    values.clear()
    if not (set_alias.length() == 0 and set_copy.length() == 1):
        return panic(message: "set clear changed a clone or lost an alias")

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
            return panic(message: "clone changed the alternative tag")

    match original:
        Choice.Present(value):
            if not (value.val == 9):
                return panic(message: "clone duplicated a nested payload record")

        Choice.Missing:
            return panic(message: "clone changed the original alternative")

    let missing = Choice.Missing.clone()
    if not (missing == Choice.Missing):
        return panic(message: "nullary alternative cloning failed")

type Node:
    value: Int
    children: List[Node]

test "mutable recursive graphs compare and clone without recursion failures":
    let left = Node(value: 1, children: [])
    let right = Node(value: 1, children: [])
    left.children.append(left)
    right.children.append(right)
    if not (left == right):
        return panic(message: "equivalent cyclic graphs compare unequal")

    let copy = left.clone()
    copy.value = 2
    if not (left.value == 1 and left != copy):
        return panic(message: "cloning a cyclic graph did not separate record fields")

    copy.children.append(Node(value: 3, children: []))
    if not (left.children.length() == 2):
        return panic(message: "cyclic graph clone was not shallow")

    right.value = 4
    if not (left != right):
        return panic(message: "cyclic equality ignored unequal fields")

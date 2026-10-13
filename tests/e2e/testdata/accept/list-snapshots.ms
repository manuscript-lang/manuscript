import List from "@std/collections.ms"
import panic from "@std/faults.ms"

fn update[T](values: List[T], value: T) -> Unit:
    values.with_value(index: 0, value: value)

test "callback snapshots retain callable values":
    let seen: List[Int] = []
    let original = fn() -> Int:
        seen.append(1)
        return 7
    let replacement = fn() -> Int:
        seen.append(2)
        return 9
    let functions = [original, original]
    functions.for_each(
        fn(value):
            seen.append(value())
            functions.fill(value: replacement, start: 0, end: 2)
    )
    if not (seen == [1, 7, 1, 7] and functions.first().unwrap()() == 9):
        return panic("snapshot lost function values")

test "fill copy and reverse detach loop snapshots":
    let filled = [1, 2, 3]
    let copied = [1, 2, 3]
    let reversed = [1, 2, 3]
    let fill_alias = filled
    let fill = filled.fill
    let copy = copied.copy_within
    let reverse = reversed.reverse
    let seen_fill: List[Int] = []
    let seen_copy: List[Int] = []
    let seen_reverse: List[Int] = []

    for value in filled:
        seen_fill.append(value)
        fill(value: 9, start: 0, end: 3)

    for value in copied:
        seen_copy.append(value)
        copy(target: 1, start: 0, end: 2)

    for value in reversed:
        seen_reverse.append(value)
        reverse()

    if not (
        seen_fill == [1, 2, 3]
        and seen_copy == [1, 2, 3]
        and seen_reverse == [1, 2, 3]
    ):
        return panic("loop snapshot was overwritten")
    if not (
        fill_alias == [9, 9, 9]
        and copied == [1, 1, 1]
        and reversed == [3, 2, 1]
    ):
        return panic("mutation lost alias identity")

test "callbacks snapshot membership through generic and bound updates":
    let values = [1, 2, 3]
    let alias = values
    let clone = values.clone()
    let fill = alias.fill
    let append = alias.append
    let each = values.for_each
    let seen: List[Int] = []
    each(
        fn(value):
            seen.append(value)
            fill(value: 8, start: 0, end: 3)
            update(values: alias, value: 9)
            append(4)
    )
    if not (
        seen == [1, 2, 3]
        and clone == [1, 2, 3]
        and alias == [9, 8, 8, 4, 4, 4]
    ):
        return panic("callback snapshot alias or clone changed")

type Child:
    value: Int

type Node:
    value: Int
    children: List[Node]

test "snapshots and clones retain nested and recursive references":
    let child = Child(1)
    let values = [child, child]
    let clone = values.clone()
    let seen: List[Int] = []
    values.for_each(
        fn(value):
            seen.append(value.value)
            value.value = value.value + 1
            values.fill(
                value: Child(9),
                start: 0,
                end: 2
            )
    )
    if not (
        seen == [1, 2]
        and child.value == 3
        and clone.first().unwrap().value == 3
    ):
        return panic("nested references were deep copied")

    let nodes: List[Node] = []
    let node = Node(value: 1, children: nodes)
    nodes.append(node)
    let outer = nodes.clone()
    nodes.for_each(
        fn(value):
            value.children.append(value)
    )
    if not (
        outer.length() == 1
        and outer.first().unwrap().children.length() == 2
        and node.children.length() == 2
    ):
        return panic("recursive references lost identity")

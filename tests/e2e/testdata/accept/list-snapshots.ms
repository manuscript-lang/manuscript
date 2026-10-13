import List from "@std/collections.ms"
import panic from "@std/faults.ms"

test "growth nested snapshots self splice and overlapping copy preserve membership":
    let growing = [1]
    let alias = growing
    let old: List[Int] = []

    for value in growing:
        old.append(value)

        while growing.length() < 128:
            growing.append(growing.length() + 1)

        growing.with_value(index: 0, value: 9)

    if not (
        old == [1]
        and alias.length() == 128
        and alias.first() == some(9)
    ):
        return panic("growth lost membership or alias update")

    let nested = [1, 2, 3]
    let outer: List[Int] = []
    let before: List[Int] = []
    let after: List[Int] = []

    for value in nested:
        outer.append(value)

        if value == 1:
            for inner in nested:
                before.append(inner)

                if inner == 1:
                    nested.with_value(index: 0, value: 9)

            for inner in nested:
                after.append(inner)

                if inner == 9:
                    nested.reverse()

    if not (
        outer == [1, 2, 3]
        and before == [1, 2, 3]
        and after == [9, 2, 3]
        and nested == [3, 2, 9]
    ):
        return panic("nested snapshots changed across detach")

    let self_list = [1, 2, 3]
    let seen_self: List[Int] = []

    for value in self_list:
        seen_self.append(value)

        if value == 1:
            self_list.with_values(start: 1, delete_count: 1, replacement: self_list)

    if not (seen_self == [1, 2, 3] and self_list == [1, 1, 2, 3, 3]):
        return panic("self splice overwrote snapshot")

    let backward = [1, 2, 3]
    let truncated = [1, 2, 3]
    let seen_backward: List[Int] = []
    let seen_truncated: List[Int] = []

    for value in backward:
        seen_backward.append(value)

        if value == 1:
            backward.copy_within(target: 0, start: 1, end: 3)

    for value in truncated:
        seen_truncated.append(value)

        if value == 1:
            truncated.copy_within(target: 2, start: 0, end: 3)

    if not (
        seen_backward == [1, 2, 3]
        and seen_truncated == [1, 2, 3]
        and backward == [2, 3, 3]
        and truncated == [1, 2, 1]
    ):
        return panic("overlapping copy overwrote snapshot or changed truncation")

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

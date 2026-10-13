import panic from "@std/faults.ms"

fn replace[T](values: List[T], value: T) -> Unit:
    values.with_value(index: 1, value: value)

test "range observes backing writes and keeps initial length":
    let values = [1, 2, 3]
    let alias = values
    let clone = values.clone()
    let seen: List[Int] = []
    var index = 0

    for value in values:
        seen.append(value)

        if index == 0:
            values.fill(value: 9, start: 0, end: 3)

        values.append(4)
        index = index + 1

    if not (
        seen == [1, 9, 9]
        and index == 3
        and alias.length() == 6
        and clone == [1, 2, 3]
    ):
        return panic("range copied backing or reread length")

test "append growth preserves captured array and current alias":
    let values = [1, 2, 3]
    let alias = values
    let append = values.append
    let seen: List[Int] = []
    var index = 0

    for value in values:
        seen.append(value)

        if index == 0:
            append(4)
            replace(values: alias, value: 9)

        index = index + 1

    if not (seen == [1, 2, 3] and alias == [1, 9, 3, 4]):
        return panic("growth switched the captured backing array")

test "callbacks use current backing and stored methods retain aliases":
    let values = [1, 2, 3]
    let clone = values.clone()
    let each = values.for_each
    let seen: List[Int] = []
    each(
        fn(value):
            seen.append(value)
            values.fill(value: 8, start: 0, end: 3)
    )
    if not (
        seen == [1, 8, 8]
        and clone == [1, 2, 3]
        and values == [8, 8, 8]
    ):
        return panic("callback copied membership or clone shared outer storage")

    let mapped = [1, 2, 3]
    let output = mapped.map(
        fn(value):
            mapped.fill(value: 9, start: 0, end: 3)
            return value + 1
    )
    if not (output == [2, 10, 10] and mapped == [9, 9, 9]):
        return panic("map did not capture backing once")

test "nested reverse copy shrink and self splice follow initial headers":
    let values = [1, 2, 3]
    let outer: List[Int] = []
    let inner: List[Int] = []
    var index = 0

    for value in values:
        outer.append(value)

        if index == 0:
            values.reverse()

            for item in values:
                inner.append(item)

        index = index + 1

    if not (outer == [1, 2, 1] and inner == [3, 2, 1]):
        return panic("nested range did not observe reverse")

    let backward = [1, 2, 3]
    let truncated = [1, 2, 3]
    let seen_backward: List[Int] = []
    let seen_truncated: List[Int] = []
    var count = 0

    for value in backward:
        seen_backward.append(value)

        if count == 0:
            backward.copy_within(target: 0, start: 1, end: 3)

        count = count + 1

    count = 0

    for value in truncated:
        seen_truncated.append(value)

        if count == 0:
            truncated.copy_within(target: 2, start: 0, end: 3)

        count = count + 1

    if not (seen_backward == [1, 3, 3] and seen_truncated == [1, 2, 1]):
        return panic("copy overlap did not update range backing")

    let shrinking = [1, 2, 3]
    let seen_shrinking: List[Int] = []
    count = 0

    for value in shrinking:
        seen_shrinking.append(value + 1)

        if not shrinking.is_empty():
            shrinking.without(0)

        count = count + 1

    if not (
        count == 3
        and shrinking.is_empty()
        and seen_shrinking == [2, 4, 4]
    ):
        return panic("shrink changed captured traversal length")

    let self_list = [1, 2, 3]
    let seen_self: List[Int] = []
    count = 0

    for value in self_list:
        seen_self.append(value)

        if count == 0:
            self_list.with_values(start: 1, delete_count: 1, replacement: self_list)

        count = count + 1

    if not (seen_self == [1, 2, 3] and self_list == [1, 1, 2, 3, 3]):
        return panic("self splice growth switched range backing")

type Child:
    value: Int

type Node:
    children: List[Node]

test "clone slice and nested references retain their own contracts":
    let child = Child(1)
    let values = [child, child]
    let clone = values.clone()
    let slice = values.slice(start: 0, end: 2).unwrap()
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
        seen == [1, 9]
        and child.value == 2
        and clone.first().unwrap().value == 2
        and slice.first().unwrap().value == 2
    ):
        return panic("reference sharing or explicit outer copy changed")

    let children: List[Node] = []
    let node = Node(children)
    children.append(node)
    var count = 0
    children.for_each(
        fn(value):
            value.children.append(value)
    )

    for ignored in children:
        count = count + 1

    if not (count == 2 and node.children.length() == 2):
        return panic("recursive callback extended its own range")

test "function values can replace later backing elements":
    let seen: List[Int] = []
    let original = fn() -> Int:
        seen.append(1)
        return 7
    let replacement = fn() -> Int:
        seen.append(2)
        return 9
    let functions = [original, original]
    let clone = functions.clone()
    functions.for_each(
        fn(value):
            seen.append(value())
            functions.fill(value: replacement, start: 0, end: 2)
    )
    if not (seen == [1, 7, 2, 9] and clone.first().unwrap()() == 7):
        return panic("function callback copied backing or lost clone")

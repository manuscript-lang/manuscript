# conform: tags=aliasing,closures,control-flow,faults,formatter,generics,lists,modules,mutation,parser,records,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/list-go-range.ms
import {expect_false} from "@std/testing.ms"

fn replace[T](values: List[T], value: T) Unit:
    values.set(1, value)

test "range observes backing writes and keeps initial length":
    let values = [1, 2, 3]
    let alias = values
    let clone = values.clone()
    let seen: List[Int] = []
    var index = 0

    for value in values:
        seen.append(value)
        if index == 0:
            values.fill(9, 0, 3)
        values.append(4)
        index += 1

    try expect_false(
        not (
            seen == [1, 9, 9]
            and index == 3
            and alias.length() == 6
            and clone == [1, 2, 3]
        )
    )

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
            replace(alias, 9)

        index += 1

    try expect_false(not (seen == [1, 2, 3] and alias == [1, 9, 3, 4]))

test "callbacks use current backing and stored methods retain aliases":
    let values = [1, 2, 3]
    let clone = values.clone()
    let each = values.for_each
    let seen: List[Int] = []
    each(
        fn(value):
            seen.append(value)
            values.fill(8, 0, 3)
    )
    try expect_false(
        not (seen == [1, 8, 8] and clone == [1, 2, 3] and values == [8, 8, 8])
    )
    let mapped = [1, 2, 3]
    let output = mapped.map(
        fn(value):
            mapped.fill(9, 0, 3)
            return value + 1
    )
    try expect_false(not (output == [2, 10, 10] and mapped == [9, 9, 9]))

test "nested reverse copy shrink and self splice follow initial headers":
    let values = [1, 2, 3]
    let outer: List[Int] = []
    let inner: List[Int] = []
    var index = 0

    for value in values:
        outer.append(value)

        if index == 0:
            values.reverse_in_place()
            for item in values:
                inner.append(item)

        index += 1

    try expect_false(not (outer == [1, 2, 1] and inner == [3, 2, 1]))
    let backward = [1, 2, 3]
    let truncated = [1, 2, 3]
    let seen_backward: List[Int] = []
    let seen_truncated: List[Int] = []
    var count = 0

    for value in backward:
        seen_backward.append(value)
        if count == 0:
            backward.copy_within(0, 1, 3)
        count += 1

    count = 0

    for value in truncated:
        seen_truncated.append(value)
        if count == 0:
            truncated.copy_within(2, 0, 3)
        count += 1

    try expect_false(not (seen_backward == [1, 3, 3] and seen_truncated == [1, 2, 1]))
    let shrinking = [1, 2, 3]
    let seen_shrinking: List[Int] = []
    count = 0

    for value in shrinking:
        seen_shrinking.append(value + 1)
        if not shrinking.is_empty():
            shrinking.remove(0)
        count += 1

    try expect_false(
        not (
            count == 3
            and shrinking.is_empty()
            and seen_shrinking == [2, 4, 4]
        )
    )
    let self_list = [1, 2, 3]
    let seen_self: List[Int] = []
    count = 0

    for value in self_list:
        seen_self.append(value)
        if count == 0:
            self_list.splice(1, 1, self_list)
        count += 1

    try expect_false(not (seen_self == [1, 2, 3] and self_list == [1, 1, 2, 3, 3]))

type Child:
    value: Int

type Node:
    children: List[Node]

test "clone slice and nested references retain their own contracts":
    let child = Child(1)
    let values = [child, child]
    let clone = values.clone()
    let slice = values.slice(0, 2).get()
    let seen: List[Int] = []
    values.for_each(
        fn(value):
            seen.append(value.value)
            value.value += 1
            values.fill(Child(9), 0, 2)
    )
    try expect_false(
        not (
            seen == [1, 9]
            and child.value == 2
            and clone.first().get().value == 2
            and slice.first().get().value == 2
        )
    )
    let children: List[Node] = []
    let node = Node(children)
    children.append(node)
    var count = 0
    children.for_each(
        fn(value):
            value.children.append(value)
    )
    for ignored in children:
        count += 1
    try expect_false(not (count == 2 and node.children.length() == 2))

test "function values can replace later backing elements":
    let seen: List[Int] = []
    let original = fn() Int:
        seen.append(1)
        return 7
    let replacement = fn() Int:
        seen.append(2)
        return 9
    let functions = [original, original]
    let clone = functions.clone()
    functions.for_each(
        fn(value):
            seen.append(value())
            functions.fill(replacement, 0, 2)
    )
    try expect_false(not (seen == [1, 7, 2, 9] and clone.first().get()() == 7))

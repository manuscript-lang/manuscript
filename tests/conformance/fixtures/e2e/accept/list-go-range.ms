# conform: tags=aliasing,closures,control-flow,faults,generics,lists,modules,mutation,records,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/list-go-range.ms
import {expect_false} from "@std/testing.ms"

fn replace[T](var values: List[T], value: T) Unit:
    values.set(1, value)

test "range iterates a snapshot while the live list changes":
    var values = [1, 2, 3]
    let clone = values.clone()
    var seen: List[Int] = []
    var index = 0

    for value in values.clone():
        seen.append(value)
        if index == 0:
            values.fill(9, 0, 3)
        values.append(4)
        index += 1

    try expect_false(
        not (
            seen == [1, 2, 3]
            and index == 3
            and values == [9, 9, 9, 4, 4, 4]
            and clone == [1, 2, 3]
        )
    )

test "append growth does not change the iterated snapshot":
    var values = [1, 2, 3]
    var seen: List[Int] = []
    var index = 0

    for value in values.clone():
        seen.append(value)

        if index == 0:
            values.append(4)
            replace(var values, 9)

        index += 1

    try expect_false(not (seen == [1, 2, 3] and values == [1, 9, 3, 4]))

test "callbacks run over snapshots and stored methods keep their receiver copy":
    var values = [1, 2, 3]
    let clone = values.clone()
    let each = values.clone().for_each
    var seen: List[Int] = []

    each(
        fn(value):
            seen.append(value)
            values.fill(8, 0, 3)
    )

    try expect_false(
        not (seen == [1, 2, 3] and clone == [1, 2, 3] and values == [8, 8, 8])
    )

    var mapped = [1, 2, 3]

    let output = mapped.clone().map(
        fn(value):
            mapped.fill(9, 0, 3)
            return value + 1
    )

    try expect_false(not (output == [2, 3, 4] and mapped == [9, 9, 9]))

test "nested reverse copy shrink and self splice iterate snapshots":
    var values = [1, 2, 3]
    var outer: List[Int] = []
    var inner: List[Int] = []
    var index = 0

    for value in values.clone():
        outer.append(value)

        if index == 0:
            values.reverse_in_place()
            for item in values.clone():
                inner.append(item)

        index += 1

    try expect_false(not (outer == [1, 2, 3] and inner == [3, 2, 1]))

    var backward = [1, 2, 3]
    var truncated = [1, 2, 3]
    var seen_backward: List[Int] = []
    var seen_truncated: List[Int] = []
    var count = 0

    for value in backward.clone():
        seen_backward.append(value)
        if count == 0:
            backward.copy_within(0, 1, 3)
        count += 1

    count = 0

    for value in truncated.clone():
        seen_truncated.append(value)
        if count == 0:
            truncated.copy_within(2, 0, 3)
        count += 1

    try expect_false(
        not (
            seen_backward == [1, 2, 3]
            and seen_truncated == [1, 2, 3]
            and backward == [2, 3, 3]
            and truncated == [1, 2, 1]
        )
    )

    var shrinking = [1, 2, 3]
    var seen_shrinking: List[Int] = []
    count = 0

    for value in shrinking.clone():
        seen_shrinking.append(value + 1)
        if not shrinking.is_empty():
            shrinking.remove(0)
        count += 1

    try expect_false(
        not (
            count == 3
            and shrinking.is_empty()
            and seen_shrinking == [2, 3, 4]
        )
    )

    var self_list = [1, 2, 3]
    var seen_self: List[Int] = []
    count = 0

    for value in self_list.clone():
        seen_self.append(value)
        if count == 0:
            self_list.splice(1, 1, self_list.clone())
        count += 1

    try expect_false(not (seen_self == [1, 2, 3] and self_list == [1, 1, 2, 3, 3]))

type Child:
    value: Int

type Node:
    children: List[Node]

test "clone slice and nested values keep their own contracts":
    let child = Child(1)
    var values = [child.clone(), child.clone()]
    let clone = values.clone()
    let slice = values.slice(0, 2).get().clone()
    var seen: List[Int] = []

    (
        values.clone().for_each(
            fn(value):
                seen.append(value.value)
                values.fill(Child(9), 0, 2)
        )
    )

    try expect_false(
        not (
            seen == [1, 1]
            and child.value == 1
            and clone.first().get().value == 1
            and slice.first().get().value == 1
            and values.first().get().value == 9
        )
    )

    var children: List[Node] = [Node([])]
    var count = 0
    children.clone().for_each(
        fn(value):
            children.append(Node([value.clone()]))
    )
    for ignored in children.clone():
        count += 1
    try expect_false(not (count == 2 and children.last().get().children.length() == 1))

test "function values can replace later backing elements":
    var seen: List[Int] = []
    let original = fn() Int: 7
    let replacement = fn() Int: 9
    let twin = fn() Int: 7
    var functions = [original, twin]
    let clone = functions.clone()

    (
        functions.clone().for_each(
            fn(value):
                seen.append(value())
                functions.fill(replacement, 0, 2)
        )
    )

    try expect_false(
        not (
            seen == [7, 7]
            and clone.first().get()() == 7
            and functions.first().get()() == 9
        )
    )

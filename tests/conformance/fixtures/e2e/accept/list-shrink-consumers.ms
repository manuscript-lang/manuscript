# conform: tags=aliasing,alternatives,closures,control-flow,faults,generics,interfaces,lists,match,modules,mutation,numbers,records,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/list-shrink-consumers.ms
import {expect_equal, expect_false, expect_true} from "@std/testing.ms"

type Visits:
    count: Int

fn mutate[T](values: List[T], mode: String, replacement: T) Unit:
    if mode == "remove":
        values.remove(0)
    if mode == "splice":
        values.splice(start: 1, delete_count: 2, replacement: [replacement])
    if mode == "clear" or mode == "clear_append":
        values.splice(start: 0, delete_count: values.length(), replacement: [])

    if mode == "clear_append":
        values.append(replacement)
        values.append(replacement)

fn observe[T](
    values: List[T],
    mode: String,
    replacement: T,
    callback: Bool
) Result[List[T], Error]:
    let seen: List[T] = []
    let visits = Visits(0)
    let visit = fn(value: T) Unit:
        seen.append(value)
        if visits.count == 0:
            mutate(values: values, mode: mode, replacement: replacement)
        visits.count = visits.count + 1

    if callback:
        let each = values.for_each
        each(visit)
    else:
        for value in values:
            visit(value)

    visits.count | try expect_equal(expected: 3)
    return ok(seen)

fn expected[T](mode: String, first: T, second: T, last: T, replacement: T) List[T]:
    if mode == "remove": return [first, last, last]
    if mode == "splice": return [first, replacement, last]
    if mode == "clear_append": return [first, replacement, last]

    return [first, second, last]

fn remaining[T](mode: String, first: T, second: T, last: T, replacement: T) List[T]:
    if mode == "remove": return [second, last]
    if mode == "splice": return [first, replacement]
    if mode == "clear_append": return [replacement, replacement]

    return []

test "Int consumers see valid shifted and retained tail values":
    for callback in [false, true]:
        for mode in ["remove", "splice", "clear", "clear_append"]:
            let values = [1, 2, 3]
            let alias = values
            let clone = values.clone()
            let seen = (try observe(values, mode, 9, callback))
            let want = expected(mode, 1, 2, 3, 9)
            var total = 0
            var wanted = 0
            for value in seen: total = total + value
            for value in want: wanted = wanted + value
            (
                not (
                    total == wanted
                    and seen == want
                    and alias == remaining(mode, 1, 2, 3, 9)
                    and clone == [1, 2, 3]
                )
            ) | try expect_false

test "Float consumers see valid shifted and retained tail values":
    for callback in [false, true]:
        for mode in ["remove", "splice", "clear", "clear_append"]:
            let values = [1.5, 2.5, 3.5]
            let clone = values.clone()
            let seen = (try observe(values, mode, 9.5, callback))
            let want = expected(mode, 1.5, 2.5, 3.5, 9.5)
            var total = 0.0
            var wanted = 0.0
            for value in seen: total = total + value
            for value in want: wanted = wanted + value
            (
                not (
                    total == wanted
                    and seen == want
                    and values == remaining(
                        mode,
                        1.5,
                        2.5,
                        3.5,
                        9.5
                    )
                    and clone == [1.5, 2.5, 3.5]
                )
            ) | try expect_false

test "String consumers see valid shifted and retained tail values":
    for callback in [false, true]:
        for mode in ["remove", "splice", "clear", "clear_append"]:
            let values = ["a", "bb", "ccc"]
            let clone = values.clone()
            let seen = (try observe(values, mode, "replacement", callback))
            let want = expected(mode, "a", "bb", "ccc", "replacement")
            var text = ""
            for value in seen: text = text + value
            (
                not (
                    text == want.join("")
                    and seen == want
                    and values == remaining(
                        mode,
                        "a",
                        "bb",
                        "ccc",
                        "replacement"
                    )
                    and clone == ["a", "bb", "ccc"]
                )
            ) | try expect_false

type Payload:
    value: Int

test "record consumers retain shallow references after shrink":
    for callback in [false, true]:
        for mode in ["remove", "splice", "clear", "clear_append"]:
            let first = Payload(1)
            let second = Payload(2)
            let last = Payload(3)
            let replacement = Payload(9)
            let values = [first, second, last]
            let clone = values.clone()
            let seen = (try observe(values, mode, replacement, callback))
            let want = expected(mode, first, second, last, replacement)
            var total = 0
            var wanted = 0
            for value in seen: total = total + value.value
            for value in want: wanted = wanted + value.value
            (
                not (
                    total == wanted
                    and seen == want
                    and values == remaining(
                        mode,
                        first,
                        second,
                        last,
                        replacement
                    )
                )
            ) | try expect_false
            last.value = 11
            (not (seen.last().get().value == 11 and clone.last().get().value == 11)) | try expect_false

type Choice:
    case number(value: Int)
    case label(value: String)

fn score(value: Choice) Int:
    match value:
        number(count): return count
        label(text): return text.length()

test "alternative consumers retain tags and payloads after shrink":
    for callback in [false, true]:
        for mode in ["remove", "splice", "clear", "clear_append"]:
            let first: Choice = number(1)
            let second: Choice = label("bb")
            let last: Choice = number(3)
            let replacement: Choice = label("replacement")
            let values = [first, second, last]
            let seen = (try observe(values, mode, replacement, callback))
            let want = expected(mode, first, second, last, replacement)
            var total = 0
            var wanted = 0
            for value in seen: total = total + score(value)
            for value in want: wanted = wanted + score(value)
            (
                not (
                    total == wanted
                    and seen == want
                    and values == remaining(
                        mode,
                        first,
                        second,
                        last,
                        replacement
                    )
                )
            ) | try expect_false

test "nested list consumers retain inner handles after shrink":
    for callback in [false, true]:
        for mode in ["remove", "splice", "clear", "clear_append"]:
            let first = [1]
            let second = [2]
            let last = [3]
            let replacement = [9]
            let values = [first, second, last]
            let clone = values.clone()
            let seen = (try observe(values, mode, replacement, callback))
            let want = expected(mode, first, second, last, replacement)
            var total = 0
            var wanted = 0
            for value in seen: total = total + value.first().get()
            for value in want: wanted = wanted + value.first().get()
            (
                not (
                    total == wanted
                    and seen == want
                    and values == remaining(
                        mode,
                        first,
                        second,
                        last,
                        replacement
                    )
                )
            ) | try expect_false
            last.append(11)
            try expect_true(
                (
                    seen.last().get() == [3, 11]
                    and clone.last().get() == [3, 11]
                )
            )

test "map and folds consume valid retained cells":
    let mapped = [1, 2, 3]
    let visits = Visits(0)
    let output = mapped.map(
        fn(value):
            if visits.count == 0: mapped.remove(0)
            visits.count = visits.count + 1
            return value + 10
    )
    (output == [11, 13, 13] and mapped == [2, 3]) | try expect_true
    let folded = [1, 2, 3]
    visits.count = 0
    let total = folded.fold(
        0,
        fn(accumulator, value):
            if visits.count == 0: folded.splice(
                start: 0,
                delete_count: 3,
                replacement: []
            )
            visits.count = visits.count + 1
            return accumulator + value
    )
    (total == 6 and folded.is_empty() and visits.count == 3) | try expect_true
    let reversed = [1, 2, 3]
    visits.count = 0
    let backwards = reversed.fold_right(
        0,
        fn(accumulator, value):
            if visits.count == 0: reversed.remove(0)
            visits.count = visits.count + 1
            return accumulator * 10 + value
    )
    (backwards == 332 and reversed == [2, 3] and visits.count == 3) | try expect_true

interface ReadValue:
    fn read() Int

impl ReadValue for Payload:
    fn read() Int: self.value

test "interface view consumers dispatch after shrink":
    for callback in [false, true]:
        for mode in ["remove", "splice", "clear", "clear_append"]:
            let last_record = Payload(3)
            let first = ReadValue(Payload(1))
            let second = ReadValue(Payload(2))
            let last = ReadValue(last_record)
            let replacement = ReadValue(Payload(9))
            let values = [first, second, last]
            let clone = values.clone()
            let seen = (try observe(values, mode, replacement, callback))
            let want = expected(mode, first, second, last, replacement)
            var total = 0
            var wanted = 0
            for value in seen: total = total + value.read()
            for value in want: wanted = wanted + value.read()
            (
                not (
                    total == wanted
                    and values.length() == remaining(
                        mode,
                        first,
                        second,
                        last,
                        replacement
                    ).length()
                )
            ) | try expect_false
            last_record.value = 11
            (not (seen.last().get().read() == 11 and clone.last().get().read() == 11)) | try expect_false

test "find returns the value passed to a mutating predicate":
    let forward = [1, 2, 3]
    let found = forward.find(
        fn(value):
            forward.remove(0)
            return value == 1
    )
    (found.get() == 1 and forward == [2, 3]) | try expect_true
    let replaced = [1, 2, 3]
    let original = replaced.find(
        fn(value):
            replaced.set(0, 9)
            return value == 1
    )
    (original.get() == 1 and replaced == [9, 2, 3]) | try expect_true
    let reverse = [1, 2, 3]
    let last = reverse.find_last(
        fn(value):
            if value == 2: reverse.remove(1)
            return value == 2
    )
    (last.get() == 2 and reverse == [1, 3]) | try expect_true
    let last_replaced = [1, 2, 3]
    let before = last_replaced.find_last(
        fn(value):
            last_replaced.set(2, 9)
            return value == 3
    )
    (before.get() == 3 and last_replaced == [1, 2, 9]) | try expect_true
    let indexes = [1, 2, 3]
    let index = indexes.find_index(
        fn(value):
            indexes.remove(0)
            return value == 1
    )
    let reverse_indexes = [1, 2, 3]
    let last_index = reverse_indexes.find_last_index(
        fn(value):
            if value == 2: reverse_indexes.remove(1)
            return value == 2
    )
    (index.get() == 0 and last_index.get() == 1) | try expect_true
    let record = Payload(1)
    let records = [record, Payload(2)]
    let retained = (
        records
        .find(
            fn(value):
                let matches = value.value == 1
                value.value = 7
                records.set(0, Payload(9))
                return matches
        )
        .get()
    )
    (
        not (
            retained.value == 7
            and record.value == 7
            and records.first().get().value == 9
        )
    ) | try expect_false

test "preferred List mutators and explicit reversed copy preserve aliases":
    let values = [1, 2, 3]
    let alias = values
    let clone = values.clone()
    let set = values.set
    let remove = values.remove
    let seen: List[Int] = []

    for value in values:
        seen.append(value)

        if seen.length() == 1:
            set(index: 1, value: 9)
            remove(index: 0)

    (seen == [1, 3, 3] and alias == [9, 3] and clone == [1, 2, 3]) | try expect_true
    let reverse_in_place = values.reverse_in_place
    let returned = reverse_in_place()
    returned.append(4)
    values | try expect_equal(expected: [3, 9, 4])
    let reversed = values.reversed
    let separate = reversed()
    values.set(1, 5)
    (separate == [4, 9, 3] and values == [3, 5, 4]) | try expect_true
    let child = Payload(1)
    let children = [child, Payload(2)]
    let shallow = children.reversed()
    child.value = 7
    children.remove(0)
    (shallow.last().get().value == 7 and children.length() == 1) | try expect_true

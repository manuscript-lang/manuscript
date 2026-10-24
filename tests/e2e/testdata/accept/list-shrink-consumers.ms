from "@std/testing.ms" import expect_equal, expect_false, expect_true

type Visits:
    count: Int

def mutate[T](var values: List[T], mode: String, fill: List[T]) -> Unit:
    if mode == "remove":
        values.remove(0)
    if mode == "splice":
        values.splice(start: 1, delete_count: 2, replacement: fill.clone())
    if mode == "clear" or mode == "clear_append":
        values.splice(start: 0, delete_count: values.length(), replacement: [])

    if mode == "clear_append":
        values.splice(start: 0, delete_count: 0, replacement: fill.clone())
        values.splice(start: 0, delete_count: 0, replacement: fill)

def step[T](
    var seen: List[T], var visits: Visits, var values: List[T], value: T, mode: String,
    fill: List[T]
) -> Unit:
    seen.append(value)
    if visits.count == 0:
        mutate(values: var values, mode: mode, fill: fill)
    visits.count = visits.count + 1

def observe[T](var values: List[T], mode: String, fill: List[T], callback: Bool) -> Result[
    List[T], Error
]:
    var seen: List[T] = []
    var visits = Visits(0)

    if callback:
        (
            values
            .clone()
            .for_each(
                lambda (value: T): step(
                    var seen, var visits, var values, value, mode, fill.clone()
                )
            )
        )
    else:
        for value in values.clone():
            step(var seen, var visits, var values, value, mode, fill.clone())

    visits.count | try expect_equal(3)
    return ok(seen)

def remaining[T](mode: String, items: List[T], fill: List[T]) -> List[T]:
    var out = items
    if mode == "remove": out.remove(0)
    if mode == "splice": out.splice(
        start: 1, delete_count: 2, replacement: fill.clone()
    )
    if mode == "clear" or mode == "clear_append": out.splice(
        start: 0, delete_count: 3, replacement: []
    )

    if mode == "clear_append":
        out.splice(start: 0, delete_count: 0, replacement: fill.clone())
        out.splice(start: 0, delete_count: 0, replacement: fill)

    return out

test "Int consumers see the full snapshot while the live list shrinks":
    for callback in [False, True]:
        for mode in ["remove", "splice", "clear", "clear_append"]:
            var values = [1, 2, 3]
            let clone = values.clone()
            let want = remaining(mode, values.clone(), [9])
            let seen = (try observe(var values, mode, [9], callback))
            var total = 0
            var wanted = 0
            for value in seen: total = total + value
            for value in clone: wanted = wanted + value
            (
                not (
                    total == wanted
                    and seen == clone
                    and values == want
                    and clone == [1, 2, 3]
                )
            ) | try expect_false

test "Float consumers see the full snapshot while the live list shrinks":
    for callback in [False, True]:
        for mode in ["remove", "splice", "clear", "clear_append"]:
            var values = [1.5, 2.5, 3.5]
            let clone = values.clone()
            let want = remaining(mode, values.clone(), [9.5])
            let seen = (try observe(var values, mode, [9.5], callback))
            var total = 0.0
            var wanted = 0.0
            for value in seen: total = total + value
            for value in clone: wanted = wanted + value
            (
                not (
                    total == wanted
                    and seen == clone
                    and values == want
                    and clone == [1.5, 2.5, 3.5]
                )
            ) | try expect_false

test "String consumers see the full snapshot while the live list shrinks":
    for callback in [False, True]:
        for mode in ["remove", "splice", "clear", "clear_append"]:
            var values = ["a", "bb", "ccc"]
            let clone = values.clone()
            let want = remaining(mode, values.clone(), ["replacement"])
            let seen = (try observe(var values, mode, ["replacement"], callback))
            var text = ""
            for value in seen: text = text + value
            (
                not (
                    text == clone.join("")
                    and seen == clone
                    and values == want
                    and clone == ["a", "bb", "ccc"]
                )
            ) | try expect_false

type Payload:
    value: Int

test "record consumers keep independent copies after shrink":
    for callback in [False, True]:
        for mode in ["remove", "splice", "clear", "clear_append"]:
            var last = Payload(3)
            var values = [Payload(1), Payload(2), last.clone()]
            let clone = values.clone()
            let want = remaining(mode, values.clone(), [Payload(9)])
            let seen = (try observe(var values, mode, [Payload(9)], callback))
            var total = 0
            var wanted = 0
            for value in seen: total = total + value.value
            for value in clone: wanted = wanted + value.value
            (not (total == wanted and seen == clone and values == want)) | try expect_false
            last.value = 11
            (not (seen.last().get().value == 3 and clone.last().get().value == 3)) | try expect_false

type Choice:
    case number(value: Int)
    case label(value: String)

def score(value: Choice) -> Int:
    match value:
        case number(count): return count
        case label(text): return text.length()

test "alternative consumers retain tags and payloads after shrink":
    for callback in [False, True]:
        for mode in ["remove", "splice", "clear", "clear_append"]:
            let first: Choice = number(1)
            let second: Choice = label("bb")
            let last: Choice = number(3)
            let fill: List[Choice] = [label("replacement")]
            var values = [first.clone(), second.clone(), last.clone()]
            let want = remaining(mode, values.clone(), fill.clone())
            let seen = (try observe(var values, mode, fill, callback))
            let snapshot = [first, second, last]
            var total = 0
            var wanted = 0
            for value in seen: total = total + score(value.clone())
            for value in snapshot.clone(): wanted = wanted + score(value)
            (not (total == wanted and seen == snapshot and values == want)) | try expect_false

test "nested list consumers keep independent inner lists after shrink":
    for callback in [False, True]:
        for mode in ["remove", "splice", "clear", "clear_append"]:
            var last = [3]
            var values = [[1], [2], last.clone()]
            let clone = values.clone()
            let want = remaining(mode, values.clone(), [[9]])
            let seen = (try observe(var values, mode, [[9]], callback))
            var total = 0
            var wanted = 0
            for value in seen: total = total + value.first().get()
            for value in clone: wanted = wanted + value.first().get()
            (not (total == wanted and seen == clone and values == want)) | try expect_false
            last.append(11)
            try expect_true((seen.last().get() == [3] and clone.last().get() == [3]))

test "map and folds consume snapshots of the live list":
    var mapped = [1, 2, 3]
    var visits = Visits(0)

    let output = (
        mapped
        .clone()
        .map(
            lambda value:
                if visits.count == 0: mapped.remove(0)
                visits.count = visits.count + 1
                return value + 10
        )
    )

    (output == [11, 12, 13] and mapped == [2, 3]) | try expect_true

    var folded = [1, 2, 3]
    visits.count = 0

    let total = (
        folded
        .clone()
        .fold(
            0,
            lambda accumulator,
            value:
                if visits.count == 0: folded.splice(
                    start: 0, delete_count: 3, replacement: []
                )
                visits.count = visits.count + 1
                return accumulator + value
        )
    )

    (total == 6 and folded.is_empty() and visits.count == 3) | try expect_true

    var reversed = [1, 2, 3]
    visits.count = 0

    let backwards = (
        reversed
        .clone()
        .fold_right(
            0,
            lambda accumulator,
            value:
                if visits.count == 0: reversed.remove(0)
                visits.count = visits.count + 1
                return accumulator * 10 + value
        )
    )

    (backwards == 321 and reversed == [2, 3] and visits.count == 3) | try expect_true

interface ReadValue:
    def read() -> Int

impl ReadValue for Payload:
    def read() -> Int: self.value

test "interface view consumers dispatch after shrink":
    for callback in [False, True]:
        for mode in ["remove", "splice", "clear", "clear_append"]:
            var last_record = Payload(3)
            var values = [
                ReadValue(Payload(1)), ReadValue(Payload(2)),
                ReadValue(last_record.clone())
            ]
            let clone = values.clone()
            let want = remaining(mode, values.clone(), [ReadValue(Payload(9))])
            let seen = (
                try observe(
                    var values, mode, [ReadValue(Payload(9))], callback
                )
            )
            var total = 0
            var wanted = 0
            for value in seen: total = total + value.read()
            for value in clone.clone(): wanted = wanted + value.read()
            (not (total == wanted and values.length() == want.length())) | try expect_false
            last_record.value = 11
            (not (seen.last().get().read() == 3 and clone.last().get().read() == 3)) | try expect_false

test "find returns the value passed to a mutating predicate":
    var forward = [1, 2, 3]

    let found = forward.clone().find(
        lambda value:
            forward.remove(0)
            return value == 1
    )

    (found.get() == 1 and forward == [2, 3]) | try expect_true

    var replaced = [1, 2, 3]

    let original = (
        replaced
        .clone()
        .find(
            lambda value:
                replaced.set(0, 9)
                return value == 1
        )
    )

    (original.get() == 1 and replaced == [9, 2, 3]) | try expect_true

    var reverse = [1, 2, 3]

    let last = (
        reverse
        .clone()
        .find_last(
            lambda value:
                if value == 2: reverse.remove(1)
                return value == 2
        )
    )

    (last.get() == 2 and reverse == [1, 3]) | try expect_true

    var last_replaced = [1, 2, 3]

    let before = (
        last_replaced
        .clone()
        .find_last(
            lambda value:
                last_replaced.set(2, 9)
                return value == 3
        )
    )

    (before.get() == 3 and last_replaced == [1, 2, 9]) | try expect_true

    var indexes = [1, 2, 3]

    let index = (
        indexes
        .clone()
        .find_index(
            lambda value:
                indexes.remove(0)
                return value == 1
        )
    )

    var reverse_indexes = [1, 2, 3]

    let last_index = (
        reverse_indexes
        .clone()
        .find_last_index(
            lambda value:
                if value == 2: reverse_indexes.remove(1)
                return value == 2
        )
    )

    (index.get() == 0 and last_index.get() == 1) | try expect_true

    let record = Payload(1)
    var records = [record.clone(), Payload(2)]
    let retained = (
        records
        .clone()
        .find(
            lambda value:
                let matches = value.value == 1
                records.set(0, Payload(9))
                return matches
        )
        .get()
    )
    (
        not (
            retained.value == 1
            and record.value == 1
            and records.first().get().value == 9
        )
    ) | try expect_false

test "preferred List mutators and explicit reversed copy iterate snapshots":
    var values = [1, 2, 3]
    let clone = values.clone()
    var seen: List[Int] = []

    for value in values.clone():
        seen.append(value)

        if seen.length() == 1:
            values.set(index: 1, value: 9)
            values.remove(index: 0)

    (seen == [1, 2, 3] and values == [9, 3] and clone == [1, 2, 3]) | try expect_true
    values.reverse_in_place()
    values.append(4)
    values | try expect_equal([3, 9, 4])

    let separate = values.reversed()
    values.set(1, 5)
    (separate == [4, 9, 3] and values == [3, 5, 4]) | try expect_true

    var child = Payload(1)
    var children = [child.clone(), Payload(2)]
    let shallow = children.reversed()
    child.value = 7
    children.remove(0)
    (shallow.last().get().value == 1 and children.length() == 1) | try expect_true

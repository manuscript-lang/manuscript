import panic from "@std/faults.ms"

type Visits:
    count: Int

fn mutate[T](values: List[T], mode: String, replacement: T) -> Unit:
    if mode == "remove":
        values.without(0)

    if mode == "splice":
        values.with_values(start: 1, delete_count: 2, replacement: [replacement])

    if mode == "clear" or mode == "clear_append":
        values.with_values(
            start: 0,
            delete_count: values.length(),
            replacement: []
        )

    if mode == "clear_append":
        values.append(replacement)
        values.append(replacement)

fn observe[T](
    values: List[T],
    mode: String,
    replacement: T,
    callback: Bool
) -> List[T]:
    let seen: List[T] = []
    let visits = Visits(0)
    let visit = fn(value: T) -> Unit:
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

    if visits.count != 3:
        return panic("shrink changed captured traversal length")

    return seen

fn expected[T](
    mode: String,
    first: T,
    second: T,
    last: T,
    replacement: T
) -> List[T]:
    if mode == "remove": return [first, last, last]
    if mode == "splice": return [first, replacement, last]
    if mode == "clear_append": return [first, replacement, last]

    return [first, second, last]

fn remaining[T](
    mode: String,
    first: T,
    second: T,
    last: T,
    replacement: T
) -> List[T]:
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
            let seen = observe(
                values,
                mode,
                9,
                callback
            )
            let want = expected(
                mode,
                1,
                2,
                3,
                9
            )
            var total = 0
            var wanted = 0

            for value in seen: total = total + value

            for value in want: wanted = wanted + value

            if not (
                total == wanted
                and seen == want
                and alias == remaining(
                    mode,
                    1,
                    2,
                    3,
                    9
                )
                and clone == [1, 2, 3]
            ):
                return panic("Int shrink consumer or alias changed")

test "Float consumers see valid shifted and retained tail values":
    for callback in [false, true]:
        for mode in ["remove", "splice", "clear", "clear_append"]:
            let values = [1.5, 2.5, 3.5]
            let clone = values.clone()
            let seen = observe(
                values,
                mode,
                9.5,
                callback
            )
            let want = expected(
                mode,
                1.5,
                2.5,
                3.5,
                9.5
            )
            var total = 0.0
            var wanted = 0.0

            for value in seen: total = total + value

            for value in want: wanted = wanted + value

            if not (
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
            ):
                return panic("Float shrink consumer or clone changed")

test "String consumers see valid shifted and retained tail values":
    for callback in [false, true]:
        for mode in ["remove", "splice", "clear", "clear_append"]:
            let values = ["a", "bb", "ccc"]
            let clone = values.clone()
            let seen = observe(
                values,
                mode,
                "replacement",
                callback
            )
            let want = expected(
                mode,
                "a",
                "bb",
                "ccc",
                "replacement"
            )
            var text = ""

            for value in seen: text = text + value

            if not (
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
            ):
                return panic("String shrink consumer or clone changed")

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
            let seen = observe(
                values,
                mode,
                replacement,
                callback
            )
            let want = expected(
                mode,
                first,
                second,
                last,
                replacement
            )
            var total = 0
            var wanted = 0

            for value in seen: total = total + value.value

            for value in want: wanted = wanted + value.value

            if not (
                total == wanted
                and seen == want
                and values == remaining(
                    mode,
                    first,
                    second,
                    last,
                    replacement
                )
            ):
                return panic("record shrink consumer lost a valid reference")

            last.value = 11
            if not (
                seen.last().unwrap().value == 11
                and clone.last().unwrap().value == 11
            ):
                return panic("record references were deep copied")

type Choice:
    case number(value: Int)
    case label(value: String)

fn score(value: Choice) -> Int:
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
            let seen = observe(
                values,
                mode,
                replacement,
                callback
            )
            let want = expected(
                mode,
                first,
                second,
                last,
                replacement
            )
            var total = 0
            var wanted = 0

            for value in seen: total = total + score(value)

            for value in want: wanted = wanted + score(value)

            if not (
                total == wanted
                and seen == want
                and values == remaining(
                    mode,
                    first,
                    second,
                    last,
                    replacement
                )
            ):
                return panic("alternative shrink consumer lost a tag or payload")

test "nested list consumers retain inner handles after shrink":
    for callback in [false, true]:
        for mode in ["remove", "splice", "clear", "clear_append"]:
            let first = [1]
            let second = [2]
            let last = [3]
            let replacement = [9]
            let values = [first, second, last]
            let clone = values.clone()
            let seen = observe(
                values,
                mode,
                replacement,
                callback
            )
            let want = expected(
                mode,
                first,
                second,
                last,
                replacement
            )
            var total = 0
            var wanted = 0

            for value in seen: total = total + value.first().unwrap()

            for value in want: wanted = wanted + value.first().unwrap()

            if not (
                total == wanted
                and seen == want
                and values == remaining(
                    mode,
                    first,
                    second,
                    last,
                    replacement
                )
            ):
                return panic("nested shrink consumer lost an inner handle")

            last.append(11)
            if not (
                seen.last().unwrap() == [3, 11]
                and clone.last().unwrap() == [3, 11]
            ):
                return panic("nested references were deep copied")

test "map and folds consume valid retained cells":
    let mapped = [1, 2, 3]
    let visits = Visits(0)
    let output = mapped.map(
        fn(value):
            if visits.count == 0: mapped.without(0)

            visits.count = visits.count + 1
            return value + 10
    )
    if not (output == [11, 13, 13] and mapped == [2, 3]):
        return panic("map lost retained tail values")

    let folded = [1, 2, 3]
    visits.count = 0
    let total = folded.fold(
        0,
        fn(accumulator, value):
            if visits.count == 0: folded.with_values(
                start: 0,
                delete_count: 3,
                replacement: []
            )

            visits.count = visits.count + 1
            return accumulator + value
    )
    if not (
        total == 6
        and folded.is_empty()
        and visits.count == 3
    ):
        return panic("fold clear changed captured values or length")

    let reversed = [1, 2, 3]
    visits.count = 0
    let backwards = reversed.fold_right(
        0,
        fn(accumulator, value):
            if visits.count == 0: reversed.without(0)

            visits.count = visits.count + 1
            return accumulator * 10 + value
    )
    if not (
        backwards == 332
        and reversed == [2, 3]
        and visits.count == 3
    ):
        return panic("right fold shrink did not follow captured backing")

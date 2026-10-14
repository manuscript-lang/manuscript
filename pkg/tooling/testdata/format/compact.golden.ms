import panic from "@std/faults.ms"

fn apply(value: Int, transform: fn(value: Int) -> Int) -> Int: transform(value)

type Choice:
    case Zero
    case One
    case Other(value: Int)

fn choose(value: Choice) -> String:
    match value:
        Zero:
            return "zero # unchanged"
        # Keep this comment with the arm.
        One:
            return "one"

        Other(number):
            return "value {number}"

fn count() -> Int:
    return apply(
        value: 2,
        transform: fn(value: Int) -> Int: return (value + 10 + 20 + 30 + 40)
    )

test "compact formatting preserves behavior":
    let values = [1, 2, 2, 4, 3, 6]  # Keep this list compact.
    let nested = [[1, 2], [3, 4]]
    let invalid = ["", "[1,", "\{\"a\" 1\}", "tru", "[1] x", "\"abc"]
    let mapped = [1, 2, 3, 4, 5, 6].map(
        transform: fn(value: Int) -> Int:
            return value + 1
    )
    if values != [1, 2, 2, 4, 3, 6]: return panic("list changed")
    if nested != [[1, 2], [3, 4]]: return panic("nested list changed")
    if invalid.length != 6: return panic("literal list changed")
    if mapped != [2, 3, 4, 5, 6, 7]: return panic("callback changed")
    if count() != 102: return panic("inline callback changed")
    if choose(Choice.Zero) != "zero # unchanged": return panic("match changed")
    if choose(Choice.Other(3)) != "value 3": return panic("interpolation changed")

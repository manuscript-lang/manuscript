import panic from "@std/faults.ms"

type Counter:
    calls: Int

fn touch(counter: Counter) -> Bool:
    counter.calls = counter.calls + 1
    return true

fn fail() -> Bool:
    return panic("short-circuited operand was evaluated")

fn defaulted(flag: Bool = not (false or false)) -> Bool:
    return flag

test "boolean optimization preserves source evaluation order":
    let counter = Counter(calls: 0)
    let skipped_and = false and fail()
    let skipped_or = true or fail()
    if skipped_and or not skipped_or:
        return panic("short-circuit result changed")

    let left_and = touch(counter) and false
    let left_or = touch(counter) or true
    if (
        left_and
        or not left_or
        or counter.calls != 2
    ):
        return panic("effectful left operand was eliminated")

    let right_and = (not false) and touch(counter)
    let right_or = (not true) or touch(counter)
    if (
        not right_and
        or not right_or
        or counter.calls != 4
    ):
        return panic("effectful right operand was eliminated")

    let callback = fn() -> Bool: return not (true and false)
    if not defaulted() or not callback():
        return panic("folding defaults or closures changed the result")

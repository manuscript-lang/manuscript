import {expect_false} from "@std/testing.ms"

type Counter:
    calls: Int

fn touch(var counter: Counter) Bool:
    counter.calls = counter.calls + 1
    return true

fn unexpected(var counter: Counter) Bool:
    counter.calls = counter.calls + 1
    return false

fn defaulted(flag: Bool = not (false or false)) Bool:
    return flag

test "boolean optimization preserves source evaluation order":
    var counter = Counter(0)
    let skipped_and = false and unexpected(var counter)
    let skipped_or = true or unexpected(var counter)
    (skipped_and or not skipped_or) | try expect_false
    (counter.calls != 0) | try expect_false
    let left_and = touch(var counter) and false
    let left_or = touch(var counter) or true
    (left_and or not left_or or counter.calls != 2) | try expect_false
    let right_and = (not false) and touch(var counter)
    let right_or = (not true) or touch(var counter)
    (not right_and or not right_or or counter.calls != 4) | try expect_false
    let callback = fn(): not (true and false)
    (not defaulted() or not callback()) | try expect_false

test "bindings read only by a folded-away operand still compile":
    let only_dropped = 10
    let dropped_or = true or only_dropped > 0
    for item in [1, 2]:
        try expect_false(false and item > 0)
    try expect_false(not dropped_or)

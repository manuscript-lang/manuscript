# conform: tags=closures,control-flow,formatter,modules,parser,records,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/boolean-optimization.ms
from "@std/testing.ms" import expect_false

type Counter:
    calls: Int

def touch(var counter: Counter) -> Bool:
    counter.calls = counter.calls + 1
    return True

def unexpected(var counter: Counter) -> Bool:
    counter.calls = counter.calls + 1
    return False

def defaulted(flag: Bool = not (False or False)) -> Bool:
    return flag

test "boolean optimization preserves source evaluation order":
    var counter = Counter(0)
    let skipped_and = False and unexpected(var counter)
    let skipped_or = True or unexpected(var counter)
    (skipped_and or not skipped_or) | try expect_false
    (counter.calls != 0) | try expect_false

    let left_and = touch(var counter) and False
    let left_or = touch(var counter) or True
    (left_and or not left_or or counter.calls != 2) | try expect_false

    let right_and = (not False) and touch(var counter)
    let right_or = (not True) or touch(var counter)
    (not right_and or not right_or or counter.calls != 4) | try expect_false

    let callback = lambda: not (True and False)
    (not defaulted() or not callback()) | try expect_false

test "bindings read only by a folded-away operand still compile":
    let only_dropped = 10
    let dropped_or = True or only_dropped > 0
    for item in [1, 2]:
        try expect_false(False and item > 0)
    try expect_false(not dropped_or)

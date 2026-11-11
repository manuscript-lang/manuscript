// conform: tags=closures,control-flow,modules,records,stdlib-testing,testing,tier-core,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/boolean-optimization.ms
import expect_false from "@std/test/test.ms"

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
    skipped_and := false and unexpected(var counter)
    skipped_or := true or unexpected(var counter)
    (skipped_and or not skipped_or) | expect_false?
    (counter.calls != 0) | expect_false?

    left_and := touch(var counter) and false
    left_or := touch(var counter) or true
    (left_and or not left_or or counter.calls != 2) | expect_false?

    right_and := (not false) and touch(var counter)
    right_or := (not true) or touch(var counter)
    (not right_and or not right_or or counter.calls != 4) | expect_false?

    callback := fn: not (true and false)
    (not defaulted() or not callback()) | expect_false?

test "bindings read only by a folded-away operand still compile":
    only_dropped := 10
    dropped_or := true or only_dropped > 0
    for item in [1, 2]:
        expect_false(false and item > 0)?
    expect_false(not dropped_or)?

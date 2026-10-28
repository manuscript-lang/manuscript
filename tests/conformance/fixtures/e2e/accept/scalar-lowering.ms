# conform: tags=aliasing,closures,control-flow,generics,interfaces,interpolation,match,modules,mutation,optional,records,stdlib-cleanup,stdlib-errors,stdlib-testing,testing,tier-stdlib,try-result,scope-cleanup
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/scalar-lowering.ms
from "@std/core.ms" import TextError
from "@std/test.ms" import expect_equal, expect_false, expect_not_equal
from "@std/core.ms" import Closeable

type Counter:
    value: Int = 0

type Resource:
    counter: Counter

impl Closeable for Resource:
    var def close() -> Unit:
        self.counter.value += 1

def mark(var counter: Counter, digit: Int) -> Int:
    counter.value = counter.value * 10 + digit
    return digit

def generic[T: Equal](left: T, right: T) -> Bool: left == right

def returning_match() -> Bool:
    return True == match some(1):
        case some(_): return False
        case none: False

test "primitive equality captures operands once in order":
    var counter = Counter()
    try expect_not_equal(mark(var counter, 1), mark(var counter, 2))
    try expect_equal(counter.value, 12)

    var original = 1
    let captured = original == match some(1):
        case some(value):
            original = 2
            value
        case none: 0
    try expect_false(not captured or original != 2)

    let skipped = False and mark(var counter, 3) == 3
    let skipped_again = True or mark(var counter, 4) == 4
    try expect_false((skipped or not skipped_again or counter.value != 12))
    try expect_false("é" == f"e\u{0301}" or "λ🙂" != "λ🙂")
    try expect_false(not generic(left: True, right: True))
    try expect_false(returning_match())

def conditional(counter: Counter, take: Bool) -> Int:
    if take:
        let _resource = Resource(counter)
        return 7

    return 8

def matched(counter: Counter) -> Int:
    return match some(1):
        case some(value):
            var _resource = Resource(counter)
            return value
            0
        case none: 0

def defaulted(
    counter: Counter,
    value: Int = match some(2):
        case some(number):
            var _resource = Resource(counter)
            let _used = ()
            _resource.close()
            number
        case none: 0
) -> Int: value

def nested(counter: Counter) -> Unit:
    let callback = lambda () -> Unit:
        let _resource = Resource(counter)
        return

    callback()

def failed() -> Result[Int, TextError]: error(TextError("expected"))

def propagate(counter: Counter) -> Result[Int, TextError]:
    var _resource = Resource(counter)
    let value = try failed()
    return ok(value)
    return ok(0)

def bare_propagate() -> Result[Int, TextError]:
    let value = try failed()
    return ok(value)

def equality_propagate() -> Result[Bool, TextError]:
    let matches = (try failed()) == 0
    return ok(matches)

def bool_failed() -> Result[Bool, TextError]: error(TextError("expected"))

def nested_results(counter: Counter) -> Result[Int, TextError]:
    let child = lambda () -> Result[Bool, TextError]:
        var _resource = Resource(counter)
        let value = try bool_failed()
        return ok(value)
        return ok(False)

    let _ignored = child()
    let value = try failed()
    return ok(value)

def statement_match_try(counter: Counter) -> Result[Int, TextError]:
    match some(1):
        case some(_):
            let _resource = Resource(counter)
            let value = try failed()
            return ok(value)
        case none: return ok(0)

    return ok(-1)

def value_match_loop_try(counter: Counter) -> Result[Int, TextError]:
    var index = 0

    while index < 2:
        let _selected = match some(index):
            case some(number):
                var _resource = Resource(counter)
                let _value = try failed()
                _resource.close()
                number
            case none: 0

        index += 1

    return ok(index)

test "combined lowering retains callable state and try boundaries":
    let counter = Counter()
    try expect_false(
        (
            nested_results(counter) != Result[Int, TextError].error(
                TextError("expected")
            )
            or counter.value != 1
        )
    )
    try expect_false(
        (
            statement_match_try(counter) != Result[Int, TextError].error(
                TextError("expected")
            )
            or counter.value != 2
        )
    )
    try expect_false(
        (
            value_match_loop_try(counter) != Result[Int, TextError].error(
                TextError("expected")
            )
            or counter.value != 3
        )
    )

test "cleanup remains owned by its source callable":
    let counter = Counter()
    try expect_false(conditional(counter, take: False) != 8 or counter.value != 0)
    try expect_false(conditional(counter, take: True) != 7 or counter.value != 1)
    try expect_false(matched(counter) != 1 or counter.value != 2)
    try expect_false(defaulted(counter) != 2 or counter.value != 3)
    try expect_false(defaulted(counter, 9) != 9 or counter.value != 3)
    nested(counter)
    try expect_equal(counter.value, 4)
    try expect_false(
        (
            propagate(counter) != Result[Int, TextError].error(
                TextError("expected")
            )
            or counter.value != 5
        )
    )
    try expect_equal(
        bare_propagate(), Result[Int, TextError].error(TextError("expected"))
    )
    try expect_equal(
        equality_propagate(), Result[Bool, TextError].error(TextError("expected"))
    )

    var index = 0

    while index < 3:
        index += 1

        let _resource = Resource(counter)
        if index == 1: continue
        if index == 2: break

    try expect_equal(counter.value, 7)

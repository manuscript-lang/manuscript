from "@std/core.ms" import TextError
from "@std/test.ms" import expect_equal, expect_false, expect_not_equal, expect_ok, expect_true
from "@std/core.ms" import Closeable
from "@std/fs.ms" import filesystem

type Counter:
    value: Int = 0

type Resource:
    marker: String

# Cleanup runs on the resource's own copy, so a marker file is how a caller observes it.
impl Closeable for Resource:
    var def close() -> Unit:
        let _written = filesystem().write_file(self.marker, "closed", True)

def closed(marker: String) -> Bool: filesystem().read_file(marker).is_ok()

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

def conditional(marker: String, take: Bool) -> Int:
    if take:
        let _resource = Resource(marker.clone())
        return 7

    return 8

def matched(marker: String) -> Int:
    return match some(1):
        case some(value):
            var _resource = Resource(marker.clone())
            return value
            0
        case none: 0

def defaulted(
    marker: String,
    value: Int = match some(2):
        case some(number):
            var _resource = Resource(marker.clone())
            let _used = ()
            _resource.close()
            number
        case none: 0
) -> Int: value

def nested(marker: String) -> Unit:
    let callback = lambda () -> Unit:
        let _resource = Resource(marker.clone())
        return

    callback()

def failed() -> Result[Int, TextError]: error(TextError("expected"))

def propagate(marker: String) -> Result[Int, TextError]:
    var _resource = Resource(marker.clone())
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

def nested_results(marker: String) -> Result[Int, TextError]:
    let child = lambda () -> Result[Bool, TextError]:
        var _resource = Resource(marker.clone())
        let value = try bool_failed()
        return ok(value)
        return ok(False)

    let _ignored = child()
    let value = try failed()
    return ok(value)

def statement_match_try(marker: String) -> Result[Int, TextError]:
    match some(1):
        case some(_):
            let _resource = Resource(marker.clone())
            let value = try failed()
            return ok(value)
        case none: return ok(0)

    return ok(-1)

def value_match_loop_try(marker: String) -> Result[Int, TextError]:
    var index = 0

    while index < 2:
        let _selected = match some(index):
            case some(number):
                var _resource = Resource(marker.clone())
                let _value = try failed()
                _resource.close()
                number
            case none: 0

        index += 1

    return ok(index)

test "combined lowering retains callable state and try boundaries":
    let fs = filesystem()
    let temporary = fs.temporary("manuscript-scalar-") | try expect_ok
    let dir = temporary.path()
    let expected = Result[Int, TextError].error(TextError("expected"))
    try expect_equal(nested_results(f"{dir}/nested"), expected)
    try expect_true(closed(f"{dir}/nested"))
    try expect_equal(statement_match_try(f"{dir}/statement"), expected)
    try expect_true(closed(f"{dir}/statement"))
    try expect_equal(value_match_loop_try(f"{dir}/loop"), expected)
    try expect_true(closed(f"{dir}/loop"))

test "cleanup remains owned by its source callable":
    let fs = filesystem()
    let temporary = fs.temporary("manuscript-scalar-") | try expect_ok
    let dir = temporary.path()
    try expect_equal(conditional(f"{dir}/skipped", take: False), 8)
    try expect_false(closed(f"{dir}/skipped"))
    try expect_equal(conditional(f"{dir}/taken", take: True), 7)
    try expect_true(closed(f"{dir}/taken"))
    try expect_equal(matched(f"{dir}/matched"), 1)
    try expect_true(closed(f"{dir}/matched"))
    try expect_equal(defaulted(f"{dir}/default"), 2)
    try expect_true(closed(f"{dir}/default"))
    try expect_equal(defaulted(f"{dir}/supplied", 9), 9)
    try expect_false(closed(f"{dir}/supplied"))
    nested(f"{dir}/nested")
    try expect_true(closed(f"{dir}/nested"))
    try expect_equal(
        propagate(f"{dir}/propagated"),
        Result[Int, TextError].error(TextError("expected"))
    )
    try expect_true(closed(f"{dir}/propagated"))
    try expect_equal(
        bare_propagate(), Result[Int, TextError].error(TextError("expected"))
    )
    try expect_equal(
        equality_propagate(), Result[Bool, TextError].error(TextError("expected"))
    )

    var index = 0

    while index < 3:
        index += 1

        let _resource = Resource(f"{dir}/loop{index}")
        if index == 1: continue
        if index == 2: break

    try expect_true(closed(f"{dir}/loop1"))
    try expect_true(closed(f"{dir}/loop2"))
    try expect_false(closed(f"{dir}/loop3"))

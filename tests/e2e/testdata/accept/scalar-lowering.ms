import panic from "@std/faults.ms"
import Closeable from "@std/cleanup.ms"

type Counter:
    value: Int = 0

type Resource:
    counter: Counter

impl Closeable for Resource:
    fn close() -> Unit:
        self.counter.value = self.counter.value + 1

fn mark(counter: Counter, digit: Int) -> Int:
    counter.value = counter.value * 10 + digit
    return digit

fn generic[T: Equal](left: T, right: T) -> Bool: left == right

fn returning_match() -> Bool:
    return true == match some(1):
    some(value): return false
    none: false

test "primitive equality captures operands once in order":
    let counter = Counter()
    if mark(counter, digit: 1) == mark(counter, digit: 2):
        return panic("distinct integers compared equal")
    if counter.value != 12: return panic("operand order or count changed")

    var original = 1
    let captured = original == match some(1):
    some(value):
        original = 2
        value
    none: 0
    if not captured or original != 2: return panic(
        "left read moved past right mutation"
    )

    let skipped = false and mark(counter, digit: 3) == 3
    let skipped_again = true or mark(counter, digit: 4) == 4
    if (skipped or not skipped_again or counter.value != 12):
        return panic("comparison escaped short circuit")
    if "é" == "e\u{0301}" or "λ🙂" != "λ🙂": return panic("Unicode equality changed")
    if not generic(left: true, right: true): return panic("generic equality changed")
    if returning_match(): return panic("operand match return changed")

fn conditional(counter: Counter, take: Bool) -> Int:
    if take:
        with resource = Resource(counter): return 7
    return 8

fn matched(counter: Counter) -> Int:
    return match some(1):
    some(value):
        with resource = Resource(counter): return value
        0
    none: 0

fn defaulted(
    counter: Counter,
    value: Int = match some(2):
    some(number):
        with resource = Resource(counter):
            let used = unit
        number
    none: 0
) -> Int: value

fn nested(counter: Counter) -> Unit:
    let callback = fn() -> Unit:
        with resource = Resource(counter): return
    callback()

fn failed() -> Result[Int, String]: error("expected")

fn propagate(counter: Counter) -> Result[Int, String]:
    with resource = Resource(counter):
        let value = try failed()
        return ok(value)

    return ok(0)

fn bare_propagate() -> Result[Int, String]:
    let value = try failed()
    return ok(value)

fn equality_propagate() -> Result[Bool, String]:
    let matches = (try failed()) == 0
    return ok(matches)

fn bool_failed() -> Result[Bool, String]: error("expected")

fn nested_results(counter: Counter) -> Result[Int, String]:
    let child = fn() -> Result[Bool, String]:
        with resource = Resource(counter):
            let value = try bool_failed()
            return ok(value)

        return ok(false)
    let ignored = child()
    let value = try failed()
    return ok(value)

fn statement_match_try(counter: Counter) -> Result[Int, String]:
    match some(1):
    some(number):
        with resource = Resource(counter):
            let value = try failed()
            return ok(value)
    none: return ok(0)

    return ok(-1)

fn value_match_loop_try(counter: Counter) -> Result[Int, String]:
    var index = 0

    while index < 2:
        let selected = match some(index):
        some(number):
            with resource = Resource(counter):
                let value = try failed()
                let used = value
            number
        none: 0

        index = index + 1

    return ok(index)

test "combined lowering retains callable state and try boundaries":
    let counter = Counter()
    if (
        nested_results(counter) != Result[Int, String].error("expected")
        or counter.value != 1
    ):
        return panic("nested callable result or cleanup state leaked")
    if (
        statement_match_try(counter) != Result[Int, String].error("expected")
        or counter.value != 2
    ):
        return panic("statement match try lost cleanup")
    if (
        value_match_loop_try(counter) != Result[Int, String].error("expected")
        or counter.value != 3
    ):
        return panic("value match loop swallowed propagation")

test "cleanup remains owned by its source callable":
    let counter = Counter()
    if conditional(counter, take: false) != 8 or counter.value != 0:
        return panic("untaken cleanup ran")
    if conditional(counter, take: true) != 7 or counter.value != 1:
        return panic("conditional return cleanup lost")
    if matched(counter) != 1 or counter.value != 2:
        return panic("match source return cleanup lost")
    if defaulted(counter) != 2 or counter.value != 3:
        return panic("default match cleanup lost")
    if defaulted(counter, value: 9) != 9 or counter.value != 3:
        return panic("explicit argument ran default cleanup")

    nested(counter)
    if counter.value != 4: return panic("nested callable cleanup lost")
    if (
        propagate(counter) != Result[Int, String].error("expected")
        or counter.value != 5
    ):
        return panic("propagation cleanup changed")
    if bare_propagate() != Result[Int, String].error("expected"):
        return panic("empty unwind affected propagation")
    if equality_propagate() != Result[Bool, String].error("expected"):
        return panic("equality operand propagation changed")

    var index = 0

    while index < 3:
        index = index + 1

        with resource = Resource(counter):
            if index == 1: continue
            if index == 2: break

    if counter.value != 7: return panic("loop cleanup exits changed")

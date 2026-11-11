// conform: tags=diagnostics
// conform: phase=check
import expect_equal from "@std/test/test.ms"
import panic from "@std/faults.ms"

fn positive(value: Int) Int:
    if value > 0:
        return value
    else:
        panic(message: "positive value required")

fn discard(value: Int) Unit:
    return

test "return contracts":
    positive(value: 3) | expect_equal(expected: 3)?
    discard(value: 1) | expect_equal(expected: unit)?

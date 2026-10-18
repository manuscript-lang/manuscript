import {expect_equal} from "@std/testing.ms"

fn echo(value: String) -> String:
    return value

test "text source forms":
    echo(value: "\{literal\}") | try expect_equal(expected: "\{literal\}")
    "\u{1F600}" | try expect_equal(expected: "😀")
    "value: {3}" | try expect_equal(expected: "value: 3")
    let no_value: Unit = unit

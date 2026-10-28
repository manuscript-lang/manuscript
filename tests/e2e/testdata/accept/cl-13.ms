import expect_equal from "@std/test.ms"

fn echo(value: String) String:
    return value

test "text source forms":
    try expect_equal(echo("\{literal\}"), "\{literal\}")
    try expect_equal("\u{1F600}", "😀")
    try expect_equal("value: {3}", "value: 3")

    let _no_value: Unit = unit

from "@std/test.ms" import expect_equal

def echo(value: String) -> String:
    return value

test "text source forms":
    try expect_equal(echo("{literal}"), "{literal}")
    try expect_equal(f"\u{1F600}", "😀")
    try expect_equal(f"value: {3}", "value: 3")

    let _no_value: Unit = ()

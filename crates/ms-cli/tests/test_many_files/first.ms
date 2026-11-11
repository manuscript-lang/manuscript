import expect_equal from "@std/test/test.ms"

fn value() Int:
    return 1

test "first file":
    expect_equal(value(), 1)?

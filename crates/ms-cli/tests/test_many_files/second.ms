import expect_equal from "@std/test/test.ms"

// The same helper name as first.ms: each file is its own module of the one executable.
fn value() Int:
    return 2

test "second file":
    try expect_equal(value(), 2)

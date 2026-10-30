import expect_equal, expect_false from "@std/test.ms"

test "omitted none defaults":
    if let v = "ab".repeat(count: 2):
        try expect_equal(v, "abab")
    else:
        try expect_false(not (false))

    try expect_equal("ab".pad_start(target_length: 4, padding: "-"), "--ab")

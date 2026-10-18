import {expect_equal, expect_true} from "@std/testing.ms"

test "omitted none defaults":
    match "ab".repeat(count: 2):
        ok(v):
            try expect_equal(v, "abab")
        error(_):
            ((false) | try expect_true)

    match "ab".pad_start(target_length: 4, padding: "-"):
        ok(v):
            try expect_equal(v, "--ab")
        error(_):
            ((false) | try expect_true)

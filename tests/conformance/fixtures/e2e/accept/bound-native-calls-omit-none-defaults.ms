# conform: tags=control-flow,modules,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/bound-native-calls-omit-none-defaults.ms
from "@std/testing.ms" import expect_equal, expect_false

test "omitted none defaults":
    if let v = "ab".repeat(count: 2):
        try expect_equal(v, "abab")
    else:
        try expect_false(not (False))

    if let v = "ab".pad_start(target_length: 4, padding: "-"):
        try expect_equal(v, "--ab")
    else:
        try expect_false(not (False))

# conform: tags=modules,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/scalar-members-match-dynamic-calls.ms
import {expect_true} from "@std/testing.ms"

test "string and float members":
    let text = "héllo"
    try expect_true((text.length() == 5 and not text.is_empty() and "".is_empty()))
    try expect_true(("a".compare(other: "b") == 0 - 1 and "b".compare(other: "b") == 0))
    try expect_true((text.concat(other: "!") == "héllo!"))
    try expect_true(((0.0 / 0.0).is_nan() and not (1.0).is_nan() and (1.0).is_finite()))

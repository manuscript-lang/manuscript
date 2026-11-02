# conform: tags=match,modules,optional,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/string-parse-int-and-to-bytes-match-dynamic-calls.ms
import expect_true from "@std/test/test.ms"

fn parsed(text: String) Int:
    match text.parse_int():
        v:
            return v
        none:
            return 0 - 1

test "parse_int":
    try expect_true((parsed(text: "123") == 123))
    try expect_true((parsed(text: "-7") == 0 - 7 and parsed(text: "+8") == 8))
    try expect_true(
        (
            parsed(text: "") == 0 - 1
            and parsed(text: "-") == 0 - 1
            and parsed(text: "1x") == 0 - 1
        )
    )
    try expect_true((parsed(text: "99999999999999999999") == 0 - 1))
    try expect_true(("héllo".to_bytes().length() == 6))

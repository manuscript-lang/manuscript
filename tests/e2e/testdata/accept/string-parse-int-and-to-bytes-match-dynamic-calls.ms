from "@std/test.ms" import expect_true

def parsed(text: String) -> Int:
    match text.parse_int():
        case some(v):
            return v
        case none:
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

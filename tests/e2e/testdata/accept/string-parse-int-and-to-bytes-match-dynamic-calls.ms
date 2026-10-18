import {expect_true} from "@std/testing.ms"

fn parsed(text: String) -> Int:
    match text.parse_int():
        some(v):
            return v
        none:
            return 0 - 1

test "parse_int":
    (parsed(text: "123") == 123) | try expect_true
    (parsed(text: "-7") == 0 - 7 and parsed(text: "+8") == 8) | try expect_true
    try expect_true(
        (
            parsed(text: "") == 0 - 1
            and parsed(text: "-") == 0 - 1
            and parsed(text: "1x") == 0 - 1
        )
    )
    (parsed(text: "99999999999999999999") == 0 - 1) | try expect_true
    ("héllo".to_bytes().length() == 6) | try expect_true

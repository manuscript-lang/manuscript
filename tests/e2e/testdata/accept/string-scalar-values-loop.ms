import expect_equal from "@std/test/test.ms"

fn walked(s: String) List[Int]:
    var out: List[Int] = []
    for c in s.scalar_values():
        out.append(c)
    return out

fn digits_only(s: String) Bool:
    for c in s.scalar_values():
        if c < 48 or c > 57:
            return false
    return true

test "a scalar walk yields what the list holds":
    for s in ["", "abc", "héllo wörld ✓ 😀!", "añb"]:
        let listed = s.scalar_values()
        try expect_equal(walked(s), listed)

test "a scalar walk stops at return, break, and continue":
    try expect_equal(digits_only("12345"), true)
    try expect_equal(digits_only("12é45"), false)

    var seen = 0

    for c in "aé😀b".scalar_values():
        if c == 233:
            continue
        if c == 128512:
            break

        seen += c

    try expect_equal(seen, 97)

test "a scalar walk reads the text as it was when the loop began":
    var s = "ab"
    var total = 0

    for c in s.scalar_values():
        s = "{s}é"
        total += c

    try expect_equal(total, 195)
    try expect_equal(s, "abéé")

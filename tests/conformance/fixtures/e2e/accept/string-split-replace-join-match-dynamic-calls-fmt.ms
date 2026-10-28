# conform: tags=formatter,lists,modules,mutation,optional,parser,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/string-split-replace-join-match-dynamic-calls.ms
import expect_true from "@std/test.ms"

test "omitted and supplied caps":
    try expect_true(("a,b,c".split(separator: ",").length() == 3))
    try expect_true(("a,b,c".split(separator: ",", max_parts: some(2)).length() == 2))
    try expect_true(("a,b,c".split(separator: ",", max_parts: none).length() == 3))
    try expect_true(("".split(separator: ",").length() == 1))
    try expect_true(("abc".split(separator: "").length() == 3))
    try expect_true(("a-b-c".replace(old: "-", new: "+") == "a+b+c"))
    try expect_true(("a-b-c".replace_first(old: "-", new: "+") == "a+b-c"))
    try expect_true(("ab".replace(old: "", new: "_") == "_a_b_"))
    try expect_true(("".replace(old: "x", new: "y") == ""))
    try expect_true((["a", "b", "c"].join(separator: "-") == "a-b-c"))

    let none_left: List[String] = []
    try expect_true((none_left.join(separator: "-") == ""))

    var parts = ["x"]
    parts.append(value: "y")
    try expect_true((parts.join(separator: "") == "xy"))

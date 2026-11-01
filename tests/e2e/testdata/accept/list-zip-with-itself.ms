import expect_equal from "@std/test/test.ms"

test "a list zipped with itself pairs each element with itself":
    var names: List[String] = ["a", "b"]
    let pairs = names.zip(names)
    try expect_equal(pairs.length(), 2)
    try expect_equal(pairs[1].first, "b")
    try expect_equal(pairs[1].second, "b")
    try expect_equal(names.length(), 2)

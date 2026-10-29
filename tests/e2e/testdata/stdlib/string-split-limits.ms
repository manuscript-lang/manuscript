import expect_equal from "@std/test.ms"

test "empty separator respects scalar limits on ASCII and mixed UTF8":
    try expect_equal("abcd".split("", max_parts: 0), [])
    try expect_equal("abcd".split("", max_parts: 1), ["a"])
    try expect_equal("abcd".split("", max_parts: 2), ["a", "b"])
    try expect_equal("abcd".split("", max_parts: 10), ["a", "b", "c", "d"])
    try expect_equal("aé日😀".split("", max_parts: 1), ["a"])
    try expect_equal("aé日😀".split("", max_parts: 2), ["a", "é"])
    try expect_equal("aé日😀".split("", max_parts: 3), ["a", "é", "日"])
    try expect_equal("aé日😀".split("", max_parts: 10), ["a", "é", "日", "😀"])
    try expect_equal("".split("", max_parts: 1), [])
    try expect_equal("x".split("", max_parts: 1), ["x"])

test "four byte scalars meet the byte count lower bound exactly":
    try expect_equal("😀😀😀😀".split("", max_parts: 4), ["😀", "😀", "😀", "😀"])
    try expect_equal("😀😀😀😀".split("", max_parts: 5), ["😀", "😀", "😀", "😀"])
    try expect_equal("😀".repeat(10000).get().split("", max_parts: 1), ["😀"])
    try expect_equal("é日😀".repeat(10000).get().split("", max_parts: 2), ["é", "日"])

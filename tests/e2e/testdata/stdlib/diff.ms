import expect_close, expect_equal from "@std/test/test.ms"
import (
    close_matches,
    CloseMatchesOptions,
    UnifiedDiffOptions,
    edit_distance,
    similarity_ratio,
    unified_diff
) from "@std/data/diff.ms"

test "edit_distance counts scalar edits":
    try expect_equal(edit_distance("kitten", "sitting"), 3)
    try expect_equal(edit_distance("", "abc"), 3)
    try expect_equal(edit_distance("same", "same"), 0)
    try expect_equal(edit_distance("café", "cafe"), 1)

test "similarity_ratio runs from 0 to 1":
    try expect_close(similarity_ratio("abcd", "abd"), 6.0 / 7.0, 0.000001)
    try expect_close(similarity_ratio("", ""), 1.0, 0.000001)
    try expect_close(similarity_ratio("abc", "xyz"), 0.0, 0.000001)

test "close_matches ranks candidates":
    try expect_equal(
        close_matches(
            "appel", ["ape", "apple", "peach"],
            CloseMatchesOptions(limit: 2, cutoff: 0.6)
        ),
        ["apple", "ape"]
    )
    try expect_equal(
        close_matches(
            "appel", ["ape", "apple", "peach"], CloseMatchesOptions(limit: 1)
        ),
        ["apple"]
    )
    try expect_equal(close_matches("zzz", ["abc"]), List[String]())

test "unified_diff formats hunks":
    try expect_equal(
        unified_diff(["a", "b"], ["a", "c"], UnifiedDiffOptions(context: 1)),
        "--- a\n+++ b\n@@ -1,2 +1,2 @@\n a\n-b\n+c\n"
    )
    try expect_equal(unified_diff(["a"], ["a"]), "")
    try expect_equal(
        unified_diff(List[String](), ["x"]), "--- a\n+++ b\n@@ -0,0 +1 @@\n+x\n"
    )
    try expect_equal(
        unified_diff(["x"], List[String]()), "--- a\n+++ b\n@@ -1 +0,0 @@\n-x\n"
    )

test "unified_diff splits distant changes and names headers":
    let old = ["1", "2", "3", "4", "5", "6", "7", "8"]
    let new = ["1", "X", "3", "4", "5", "6", "7", "Y"]
    let expected = "--- old.txt\n+++ new.txt\n@@ -1,3 +1,3 @@\n 1\n-2\n+X\n 3\n@@ -7,2 +7,2 @@\n 7\n-8\n+Y\n"
    try expect_equal(
        unified_diff(
            old,
            new,
            UnifiedDiffOptions(
                context: 1, old_name: "old.txt", new_name: "new.txt"
            )
        ),
        expected
    )

test "unified_diff keeps offsets across shared leading and trailing lines":
    try expect_equal(
        unified_diff(
            ["a", "b", "c", "d", "e"], ["a", "b", "x", "d", "e"],
            UnifiedDiffOptions(context: 1)
        ),
        "--- a\n+++ b\n@@ -2,3 +2,3 @@\n b\n-c\n+x\n d\n"
    )
    try expect_equal(unified_diff(["a", "b"], ["a", "b"]), "")
    try expect_equal(
        unified_diff([], ["a"], UnifiedDiffOptions(context: 0)),
        "--- a\n+++ b\n@@ -0,0 +1 @@\n+a\n"
    )

test "unified_diff clamps a context larger than the input":
    let expected = "--- a\n+++ b\n@@ -1 +1 @@\n-before\n+after\n"
    try expect_equal(
        unified_diff(["before"], ["after"], UnifiedDiffOptions(context: 3)), expected
    )
    try expect_equal(
        unified_diff(
            ["before"], ["after"], UnifiedDiffOptions(context: 9223372036854775807)
        ),
        expected
    )
    try expect_equal(
        unified_diff(
            ["same"], ["same"], UnifiedDiffOptions(context: 9223372036854775807)
        ),
        ""
    )

test "identical text comparisons preserve scalar semantics":
    for text in ["", "same", "café🙂", "a\n\tb", "é", "\u{0}"]:
        let copy = text.clone()
        try expect_equal(edit_distance(text, copy), 0)
        try expect_equal(similarity_ratio(text, copy), 1.0)

    try expect_equal(edit_distance("é", "é"), 2)
    try expect_close(similarity_ratio("é", "é"), 0.0, 0.000001)
    try expect_equal(edit_distance("abc", "abd"), 1)
    try expect_close(similarity_ratio("abc", "abd"), 2.0 / 3.0, 0.000001)

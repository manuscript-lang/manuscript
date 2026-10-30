import BitSet from "@std/bitset.ms"
import expect_equal, expect_true, expect_false from "@std/test.ms"

test "bitset predicates agree with algebra for unequal and trailing zero words":
    let cases: List[List[Int]] = [
        [], [0], [1], [-1], [-9223372036854775808], [1, 0], [0, 1],
        [0, -9223372036854775808], [1, -1, 0], [0, 0, 0]
    ]

    for a in cases:
        for b in cases:
            let left = BitSet(words: a.clone())
            let right = BitSet(words: b.clone())
            try expect_equal(
                left.is_subset_of(right), left.difference(right).is_empty()
            )
            try expect_equal(
                left.is_superset_of(right), right.difference(left).is_empty()
            )
            try expect_equal(
                left.is_disjoint_from(right), left.intersection(right).is_empty()
            )
            try expect_equal(left.words, a)
            try expect_equal(right.words, b)

test "bitset predicates find decisive first and last words":
    for index in [0, 2047]:
        var left = BitSet()
        var right = BitSet()
        left.add(index)
        right.add(4095)
        try expect_false(left.is_subset_of(right))
        try expect_false(right.is_superset_of(left))
        try expect_true(left.is_disjoint_from(right))
        right.add(index)
        try expect_true(left.is_subset_of(right))
        try expect_true(right.is_superset_of(left))
        try expect_false(left.is_disjoint_from(right))

    var boundary = BitSet()
    boundary.add(63)
    boundary.add(64)
    try expect_true(boundary.is_subset_of(boundary))
    try expect_true(boundary.is_superset_of(boundary))
    try expect_false(boundary.is_disjoint_from(boundary))

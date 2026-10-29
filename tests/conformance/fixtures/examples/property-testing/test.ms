import insertion_sort from "./src/main.ms"
import {check, ints, lists} from "@std/test/property.ms"
import {expect_equal, expect_true} from "@std/test.ms"

# Each property runs on 100 generated lists. A failure prints a shrunk counterexample and a seed.
test "sorting keeps every element":
    try check(
        "same elements", lists(ints(-50, 50)),
        fn xs: expect_equal(insertion_sort(xs).length(), xs.length())
    )

test "sorting is idempotent":
    try check(
        "idempotent",
        lists(ints(-50, 50)),
        fn xs: expect_equal(
            insertion_sort(insertion_sort(xs)), insertion_sort(xs)
        )
    )

test "sorted output is ordered":
    try check(
        "ordered", lists(ints(-50, 50)),
        fn xs: expect_true(is_ordered(insertion_sort(xs)))
    )

fn is_ordered(xs: List[Int]) Bool:
    for i in 1..xs.length():
        if xs[i - 1] > xs[i]:
            return false
    return true

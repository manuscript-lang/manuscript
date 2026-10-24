# conform: tags=closures,diagnostics,faults,interfaces,maps,modules,sets,stdlib-testing,testing,tier-core,try-result
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/core_parity/conformance_test.ms
from "@std/testing.ms" import expect_equal, expect_false, expect_true
from "./first.ms" import (
    first_mapped,
    first_bound_map,
    first_generic_map,
    first_lookup,
    first_failure,
    first_queries,
    first_converted,
    first_folded,
    first_key_transform,
    first_bound_keys,
    first_value_transform
)
from "./second.ms" import (
    second_mapped,
    second_failure,
    second_queries,
    second_converted,
    second_folded,
    second_key_transform,
    second_bound_keys,
    second_value_transform
)
from "./domain.ms" import Key, Cause

test "mapped output keeps lexical Hashable and Equal evidence":
    let by_id = first_mapped()
    let by_label = second_mapped()
    (by_id.length() != 1 or by_label.length() != 2) | try expect_false
    by_id.values().get(0).label | try expect_equal("1")

    let bound = first_bound_map()
    let mapped = bound(lambda n: Key(0, n.to_string()))
    mapped.length() | try expect_equal(1)

    let input = Set[Int]([1, 2])
    first_generic_map(input).length() | try expect_equal(1)
    first_lookup() | try expect_equal("found")

test "Result composition retains concrete Error and its local implementation":
    var cause = Cause(1)
    let one = first_failure(cause)
    let two = second_failure(cause)
    try expect_false(
        (one.err().message() != "first 1" or two.err().message() != "second 1")
    )
    cause.count = 2
    (cause.count != 2 or two.err().message() != "second 2") | try expect_false

test "conversions and queries retain scoped generic evidence and Error identity":
    (not (first_queries()) or not (second_queries())) | try expect_false

    var cause = Cause(1)
    let one = first_converted(cause)
    let two = second_converted(cause)
    try expect_false(
        (one.err().message() != "first 1" or two.err().message() != "second 1")
    )
    cause.count = 3
    try expect_false(
        (one.err().message() != "first 3" or two.err().message() != "second 3")
    )
    (one.to_optional().is_none()) | try expect_true

test "generic folds preserve scoped interface accumulators":
    var cause = Cause(4)
    let one = first_folded(cause)
    let two = second_folded(cause)
    (one.message() != "first 4" or two.message() != "second 4") | try expect_false
    cause.count = 5
    (one.message() != "first 5" or two.message() != "second 5") | try expect_false

test "Map transformations preserve input and output equality evidence":
    let input: Map[Int, Int] = {1: 10, 2: 20}
    let one = first_key_transform(input)
    let two = second_key_transform(input)
    (one.length() != 1 or two.length() != 2) | try expect_false
    (one.keys().get(0).label != "1" or one.values() != [20]) | try expect_false

    let bound_one = first_bound_keys()
    let bound_two = second_bound_keys()
    try expect_equal(bound_one(lambda key, value: Key(0, key.to_string())).length(), 1)
    try expect_equal(bound_two(lambda key, value: Key(0, key.to_string())).length(), 2)
    (first_value_transform() != 3 or second_value_transform() != 0) | try expect_false

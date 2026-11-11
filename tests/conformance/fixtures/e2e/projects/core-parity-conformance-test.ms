// conform: tags=closures,diagnostics,faults,interfaces,maps,modules,sets,stdlib-testing,testing,tier-core,try-result
// conform: phase=check
// conform: origin=tests/e2e/testdata/projects/core_parity/conformance_test.ms
import expect_equal, expect_false, expect_true from "@std/test/test.ms"
import (
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
) from "./first.ms"
import (
    second_mapped,
    second_failure,
    second_queries,
    second_converted,
    second_folded,
    second_key_transform,
    second_bound_keys,
    second_value_transform
) from "./second.ms"
import Key, Cause from "./domain.ms"

test "mapped output keeps lexical Hashable and Equal evidence":
    by_id := first_mapped()
    by_label := second_mapped()
    (by_id.length() != 1 or by_label.length() != 2) | expect_false?
    by_id.values().get(0).label | expect_equal("1")?

    bound := first_bound_map()
    mapped := bound(fn n: Key(0, n.to_string()))
    mapped.length() | expect_equal(1)?

    input := Set[Int]([1, 2])
    first_generic_map(input).length() | expect_equal(1)?
    first_lookup() | expect_equal("found")?

test "Result composition builds each module's own Error from the domain value":
    var cause = Cause(1)
    one := first_failure(cause)
    two := second_failure(cause)
    expect_false(
        (one.err().message != "first 1" or two.err().message != "second 1")
    )?
    cause.count = 2
    (cause.count != 2 or two.err().message != "second 1") | expect_false?

test "conversions and queries retain scoped generic evidence and a plain Error":
    (not (first_queries()) or not (second_queries())) | expect_false?

    var cause = Cause(1)
    one := first_converted(cause)
    two := second_converted(cause)
    expect_false(
        (one.err().message != "first 1" or two.err().message != "second 1")
    )?
    cause.count = 3
    expect_false(
        (one.err().message != "first 1" or two.err().message != "second 1")
    )?
    (one.to_optional().is_none()) | expect_true?

test "generic folds preserve plain Error accumulators":
    var cause = Cause(4)
    one := first_folded(cause)
    two := second_folded(cause)
    (one.message != "first 4" or two.message != "second 4") | expect_false?
    cause.count = 5
    (one.message != "first 4" or two.message != "second 4") | expect_false?

test "Map transformations preserve input and output equality evidence":
    input: Map[Int, Int] := {1: 10, 2: 20}
    one := first_key_transform(input)
    two := second_key_transform(input)
    (one.length() != 1 or two.length() != 2) | expect_false?
    (one.keys().get(0).label != "1" or one.values() != [20]) | expect_false?

    bound_one := first_bound_keys()
    bound_two := second_bound_keys()
    expect_equal(bound_one(fn key, value: Key(0, key.to_string())).length(), 1)?
    expect_equal(bound_two(fn key, value: Key(0, key.to_string())).length(), 2)?
    (first_value_transform() != 3 or second_value_transform() != 0) | expect_false?

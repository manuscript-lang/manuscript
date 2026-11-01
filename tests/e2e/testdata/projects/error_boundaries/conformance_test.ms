import expect_equal, expect_false, fail from "@std/test/test.ms"
import DomainFailure from "./domain.ms"
import (
    first_error,
    first_result,
    first_propagated,
    first_generic,
    first_box
) from "./first.ms"
import second_error, relay from "./second.ms"

test "Error boundaries retain selected local and generic implementations":
    var original = DomainFailure(7)
    let first = first_error(original)
    let second = second_error(original)
    (first.message() != "first 7" or second.message() != "second 7") | try expect_false

    let others: List[Error] = [first_generic(original), first_box(original)]
    for cause in others:
        cause.message() | try expect_equal("first 7")
    original.code = 8

    for result in [first_result(original), first_propagated(original)]:
        match result:
            ok(_):
                return fail(message: "expected domain failure")
            error(cause):
                try expect_equal(cause.message(), "first 8")

    # The view was made before the change, so it keeps its own copy and the first module's implementation.
    match relay(first):
        ok(_):
            return fail(message: "expected domain failure")
        error(cause):
            try expect_equal(cause.message(), "first 7")

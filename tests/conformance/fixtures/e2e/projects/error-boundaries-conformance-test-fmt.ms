# conform: tags=control-flow,formatter,lists,match,modules,parser,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/error_boundaries/conformance_test.ms
import expect_equal, expect_false, fail from "@std/test/test.ms"
import DomainFailure from "./domain.ms"
import first_error, first_result, first_propagated, first_generic, first_box from "./first.ms"
import second_error, relay from "./second.ms"

test "Error boundaries convert a domain value into each module's own Error":
    var original = DomainFailure(7)
    let first = first_error(original)
    let second = second_error(original)
    (first.message != "first 7" or second.message != "second 7") | try expect_false

    first_generic(original).message | try expect_equal("first 7")
    first_box(original.clone()).message | try expect_equal("box: first 7")
    original.code = 8

    let results = [first_result(original), first_propagated(original), relay(first.clone())]
    let expected = ["first 8", "first 8", "first 7"]
    for index in 0..3:
        match results.get(index):
            ok(_):
                return fail(message: "expected domain failure")
            error(cause):
                try expect_equal(cause.message, expected.get(index))

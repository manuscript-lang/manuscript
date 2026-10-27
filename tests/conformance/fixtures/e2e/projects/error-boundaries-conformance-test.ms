# conform: tags=control-flow,diagnostics,lists,match,modules,stdlib-testing,testing,tier-core,try-result
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/error_boundaries/conformance_test.ms
from "@std/test.ms" import expect_equal, expect_false, fail
from "./domain.ms" import DomainFailure
from "./first.ms" import first_error, first_result, first_propagated, first_generic, first_box
from "./second.ms" import second_error, relay

test "Error boundaries retain selected local and generic implementations":
    var original = DomainFailure(7)
    let first = first_error(original)
    let second = second_error(original)
    (first.message() != "first 7" or second.message() != "second 7") | try expect_false

    let others: List[Error] = [first_generic(original), first_box(original)]
    for cause in others:
        cause.message() | try expect_equal("first 7")
    original.code = 8

    for result in [first_result(original), first_propagated(original), relay(first)]:
        match result:
            case ok(_):
                return fail(message: "expected domain failure")
            case error(cause):
                try expect_equal(cause.message(), "first 8")

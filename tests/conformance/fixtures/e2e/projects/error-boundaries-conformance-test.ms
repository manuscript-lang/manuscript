// conform: tags=control-flow,diagnostics,lists,match,modules,stdlib-testing,testing,tier-core,try-result
// conform: phase=check
// conform: origin=tests/e2e/testdata/projects/error_boundaries/conformance_test.ms
import (
	expect_equal, expect_false, fail from "@std/test/test.ms",

	DomainFailure from "./domain.ms",
	first_box,
	first_error,
	first_generic,
	first_propagated,
	first_result from "./first.ms",
	relay, second_error from "./second.ms",
)

test "Error boundaries convert a domain value into each module's own Error":
	var original = DomainFailure(7)
	first := first_error(original)
	second := second_error(original)
	(first.message != "first 7" or second.message != "second 7") | expect_false?
	first_generic(original).message | expect_equal("first 7")?
	first_box(original.clone()).message | expect_equal("box: first 7")?
	original.code = 8

	results := [
		first_result(original), first_propagated(original), relay(first.clone())
	]
	expected := ["first 8", "first 8", "first 7"]

	for index in 0..3:
		match results.get(index):
			ok(_):
				return fail(message: "expected domain failure")
			error(cause):
				expect_equal(cause.message, expected.get(index))?

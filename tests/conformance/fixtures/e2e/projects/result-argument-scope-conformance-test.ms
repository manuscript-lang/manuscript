// conform: tags=control-flow,diagnostics,match,modules,stdlib-testing,strings,testing,tier-core,try-result
// conform: phase=check
// conform: origin=tests/e2e/testdata/projects/result_argument_scope/conformance_test.ms
import (
	expect_true, fail from "@std/test/test.ms",

	Cause from "./domain.ms",
	first, first_generic from "./first.ms",
	second, second_generic from "./second.ms",
)

fn describe(r Int!) String {
	match r {
		ok(_) => return "unexpected success"
		error(cause) => {
			return cause.message.clone()
		}
	}
}

test "each module's error conversion is kept through inference and forwarding" {
	if describe(first()) != "first 7" { return fail("lost first scope") }
	if describe(second()) != "second 7" { return fail("lost second scope") }
	if describe(first_generic()) != "first 7" {
		return fail("lost first generic evidence")
	}
	if describe(second_generic()) != "second 7" {
		return fail("lost second generic evidence")
	}
}
// expect-error: MS2002 4:1 cannot find module ./domain.ms (looked for domain.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file

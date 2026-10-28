# conform: tags=control-flow,diagnostics,match,modules,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/result_argument_scope/conformance_test.ms
import {first, first_generic} from "./first.ms"
import {second, second_generic} from "./second.ms"
import Cause from "./domain.ms"
import {expect_true, fail} from "@std/test.ms"

fn describe(r: Result[Int, Error]) String:
    match r:
        ok(_): return "unexpected success"
        error(cause):
            return cause.message()

test "local implementations remain selected after inference and forwarding":
    if describe(first()) != "first 7": return fail("lost first scope")
    if describe(second()) != "second 7": return fail("lost second scope")
    if describe(first_generic()) != "first 7": return fail(
        "lost first generic evidence"
    )
    if describe(second_generic()) != "second 7": return fail(
        "lost second generic evidence"
    )

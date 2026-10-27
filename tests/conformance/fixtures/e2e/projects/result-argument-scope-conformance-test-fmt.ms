# conform: tags=control-flow,formatter,match,modules,parser,stdlib-testing,strings,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/result_argument_scope/conformance_test.ms
from "./first.ms" import first, first_generic
from "./second.ms" import second, second_generic
from "./domain.ms" import Cause
from "@std/test.ms" import expect_true, fail

def describe(r: Result[Int, Error]) -> String:
    match r:
        case ok(_): return "unexpected success"
        case error(cause):
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

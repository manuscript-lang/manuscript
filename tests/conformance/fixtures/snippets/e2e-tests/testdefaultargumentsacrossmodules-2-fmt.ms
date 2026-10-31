# conform: tags=control-flow,formatter,modules,parser,stdlib-testing,testing,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/e2e_test.go:510 TestDefaultArgumentsAcrossModules
import defaulted from "./library.ms"
import expect_true, fail from "@std/test.ms"

fn private_value() Int:
    return 99

test "defaults use their declaration module":
    let copy = defaulted
    if defaulted() != 7 or copy() != 7 or defaulted(0) != 0:
        return fail("incorrect default scope")

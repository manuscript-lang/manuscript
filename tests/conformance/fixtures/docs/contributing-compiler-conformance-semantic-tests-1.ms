# conform: tags=control-flow,faults,modules,stdlib-faults,testing,tier-stdlib
# conform: phase=test
# conform: origin=documentation/contributing/compiler/conformance/semantic-tests.md:14
from "@std/core.ms" import panic

test "checked decrement":
    let value = 3
    if not (value - 1 > 0):
        return panic(message: "check failed")

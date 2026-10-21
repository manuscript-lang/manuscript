# conform: tags=control-flow,faults,modules,stdlib-faults,testing,tier-stdlib
# conform: phase=test
# conform: origin=pkg/build/compiler_test.go:280 FuzzCompile
import panic from "@std/core.ms"

test "list":
    let values = [1, 2]
    if not (values.length() == 2):
        return panic(message: "check failed")

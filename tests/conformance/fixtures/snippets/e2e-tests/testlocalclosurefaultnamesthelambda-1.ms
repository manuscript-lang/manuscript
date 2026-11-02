# conform: tags=closures,faults,modules,stdlib-faults,testing,tier-stdlib
# conform: phase=test
# conform: origin=tests/e2e/local_closures_test.go:11 TestLocalClosureFaultNamesTheLambda
import panic from "@std/core.ms"

fn run() Int:
    let boom = fn(value: Int) Int: panic(message: "closure failed")
    return boom(value: 1)

test "fault":
    run()

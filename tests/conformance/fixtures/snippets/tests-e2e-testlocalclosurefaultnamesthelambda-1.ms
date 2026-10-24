# conform: tags=closures,faults,modules,stdlib-faults,testing,tier-stdlib
# conform: phase=test
# conform: origin=tests/e2e/local_closures_test.go:11 TestLocalClosureFaultNamesTheLambda
from "@std/core.ms" import panic

def run() -> Int:
    let boom = lambda (value: Int) -> Int: panic(message: "closure failed")
    return boom(value: 1)

test "fault":
    run()

# conform: tags=closures,faults,formatter,modules,parser,stdlib-faults,testing,tier-stdlib
# conform: phase=parse
# conform: origin=tests/e2e/local_closures_test.go:11 TestLocalClosureFaultNamesTheLambda
import panic from "@std/faults.ms"

fn run() Int:
    let boom = fn(value: Int) Int: panic(message: "closure failed")
    return boom(value: 1)

test "fault":
    run()

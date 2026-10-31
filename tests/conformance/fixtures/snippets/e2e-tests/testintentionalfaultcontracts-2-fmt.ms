# conform: tags=closures,control-flow,faults,formatter,modules,parser,stdlib-faults,stdlib-testing,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/intentional_faults_test.go:28 TestIntentionalFaultContracts
import expect_contains, expect_fault from "@std/test.ms"
import panic from "@std/core.ms"

fn failed_initializer() Never:
    let _impossible: Int = panic(message: "initializer cannot return")

fn returned_failure() Int:
    return panic(message: "result cannot return")

fn endless() Int:
    while true:
        continue

test "Never faults propagate through initializers and returned values":
    try expect_contains(
        try expect_fault(
            fn:
                let _impossible = failed_initializer()
        ),
        "initializer cannot return"
    )
    try expect_contains(
        try expect_fault(
            fn:
                let _impossible = returned_failure()
        ),
        "result cannot return"
    )

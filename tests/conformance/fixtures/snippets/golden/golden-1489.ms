// conform: tags=diagnostics
// conform: phase=check
import expect_contains, expect_fault from "@std/test/test.ms"
import panic from "@std/faults.ms"

fn failed_initializer() Never:
    impossible: Int := panic(message: "initializer cannot return")

fn returned_failure() Int:
    return panic(message: "result cannot return")

fn endless() Int:
    while true:
        continue

test "Never faults propagate through initializers and returned values":
    expect_contains(
        expect_fault(
            fn:
                impossible := failed_initializer()
        )?,
        "initializer cannot return"
    )?
    expect_contains(
        expect_fault(
            fn:
                impossible := returned_failure()
        )?,
        "result cannot return"
    )?

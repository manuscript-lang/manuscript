# conform: tags=modules,stdlib-errors,tier-stdlib,try-result
# conform: phase=run
# conform: origin=tests/e2e/fault_locations_test.go:111 TestFaultSourceLocations
import {TextError} from "@std/core.ms"

fn crash(cause: TextError) Int:
    return 1 / 0

export fn main() Int:
    let value: Result[Int, TextError] = error(TextError("expected failure"))
    return value.or_else(crash)

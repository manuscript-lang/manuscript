# conform: tags=faults,modules,stdlib-errors,tier-stdlib,try-result
# conform: phase=run
# conform: origin=tests/e2e/fault_locations_test.go:92 TestFaultSourceLocations
import {TextError} from "@std/core.ms"

fn deep(value: Result[Int, TextError]) Int:
    return value.get()

export fn main() Int:
    return deep(error(TextError("expected failure")))

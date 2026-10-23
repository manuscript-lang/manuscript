# conform: tags=faults,formatter,modules,parser,stdlib-errors,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/fault_locations_test.go:104 TestFaultSourceLocations
import {TextError} from "@std/core.ms"

fn crash(value: Int) Int:
    return 1 / value

export fn main() Int:
    let value: Result[Int, TextError] = ok(0)
    return value.map(crash).get()

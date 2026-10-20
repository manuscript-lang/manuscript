# conform: tags=faults,formatter,modules,parser,stdlib-errors,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/fault_locations_test.go:92 TestFaultSourceLocations
import {TextError} from "@std/errors.ms"
fn deep(value: Result[Int, TextError]) Int:
    return value.get()
export fn main() Int:
    return deep(error(TextError("expected failure")))

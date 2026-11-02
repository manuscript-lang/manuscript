# conform: tags=faults,formatter,modules,parser,stdlib-errors,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/fault_locations_test.go:92 TestFaultSourceLocations
import TextError from "@std/core.ms"

fn deep(value: Int!TextError) Int:
    return value.get()

export fn main() Int:
    return deep(error(TextError("expected failure")))

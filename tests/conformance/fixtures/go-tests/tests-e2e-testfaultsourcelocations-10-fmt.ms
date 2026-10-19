# conform: tags=aliasing,formatter,modules,parser,stdlib-errors,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/fault_locations_test.go:98 TestFaultSourceLocations
import {TextError} from "@std/errors.ms"
export fn main() Int:
    let value: Result[Int, TextError] = ok(0)
    let extract = value.err
    return extract().text.scalar_length()

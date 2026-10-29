# conform: tags=aliasing,modules,stdlib-errors,tier-stdlib,try-result
# conform: phase=run
# conform: origin=tests/e2e/fault_locations_test.go:98 TestFaultSourceLocations
import TextError from "@std/core.ms"

export fn main() Int:
    let value: Result[Int, TextError] = ok(0)
    let extract = value.err
    return extract().text.scalar_length()

# conform: tags=aliasing,modules,stdlib-errors,tier-stdlib,try-result
# conform: phase=run
# conform: origin=tests/e2e/fault_locations_test.go:98 TestFaultSourceLocations
from "@std/core.ms" import TextError

export def main() -> Int:
    let value: Result[Int, TextError] = ok(0)
    let extract = value.err
    return extract().text.scalar_length()

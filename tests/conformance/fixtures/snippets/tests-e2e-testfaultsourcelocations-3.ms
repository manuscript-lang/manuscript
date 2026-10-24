# conform: tags=control-flow,faults,modules,stdlib-errors,tier-stdlib,try-result
# conform: phase=run
# conform: origin=tests/e2e/fault_locations_test.go:35 TestFaultSourceLocations
from "@std/core.ms" import TextError

def checked(n: Int) -> Result[Int, TextError]:
    if n < 0:
        return error(TextError("negative"))

    return ok(n + 1)

def chain(n: Int) -> Result[Int, TextError]:
    let value = try checked(n)
    return ok(value)

export def main() -> Int:
    return chain(9223372036854775807).get()

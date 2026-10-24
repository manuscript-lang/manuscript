# conform: tags=faults,modules,stdlib-errors,tier-stdlib,try-result
# conform: phase=run
# conform: origin=tests/e2e/fault_locations_test.go:104 TestFaultSourceLocations
from "@std/core.ms" import TextError

def crash(value: Int) -> Int:
    return 1 / value

export def main() -> Int:
    let value: Result[Int, TextError] = ok(0)
    return value.map(crash).get()

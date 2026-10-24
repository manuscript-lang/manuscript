# conform: tags=modules,stdlib-errors,tier-stdlib,try-result
# conform: phase=run
# conform: origin=tests/e2e/fault_locations_test.go:111 TestFaultSourceLocations
from "@std/core.ms" import TextError

def crash(cause: TextError) -> Int:
    return 1 / 0

export def main() -> Int:
    let value: Result[Int, TextError] = error(TextError("expected failure"))
    return value.or_else(crash)

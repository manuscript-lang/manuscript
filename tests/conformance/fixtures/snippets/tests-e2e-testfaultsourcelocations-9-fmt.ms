# conform: tags=faults,formatter,modules,parser,stdlib-errors,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/fault_locations_test.go:92 TestFaultSourceLocations
from "@std/core.ms" import TextError

def deep(value: Result[Int, TextError]) -> Int:
    return value.get()

export def main() -> Int:
    return deep(error(TextError("expected failure")))

# conform: tags=control-flow,formatter,modules,optional,parser,stdlib-io,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/fault_locations_test.go:63 TestFaultSourceLocations
from "@std/io.ms" import read_line, ReadStream, stdin

def limit() -> Int:
    return 1 / "".byte_length()

def probe(input: ReadStream) -> Bool:
    if let line = read_line(input, limit()):
        return line.is_some()

    return False

export def main() -> Int:
    if probe(stdin()): return 1

    return 0

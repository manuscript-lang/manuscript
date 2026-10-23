# conform: tags=control-flow,modules,optional,stdlib-io,tier-core
# conform: phase=run
# conform: origin=tests/e2e/fault_locations_test.go:63 TestFaultSourceLocations
import {read_line, ReadStream, stdin} from "@std/io.ms"

fn limit() Int:
    return 1 / 0

fn probe(input: ReadStream) Bool:
    if let line = read_line(input, limit()):
        return line.is_some()

    return false

export fn main() Int:
    if probe(stdin()): return 1

    return 0

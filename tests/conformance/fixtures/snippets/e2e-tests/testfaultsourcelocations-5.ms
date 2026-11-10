// conform: tags=control-flow,modules,optional,stdlib-io,tier-core
// conform: phase=run
// conform: origin=tests/e2e/fault_locations_test.go:63 TestFaultSourceLocations
import Bytes from "@std/bytes.ms"
import ReadStream, stdin from "@std/io/io.ms"

fn limit() Int:
    return 1 / "".byte_length()

fn probe(input: ReadStream[Bytes]) Bool:
    if line := read_line(input, limit()):
        return not line.is_empty()

    return false

export fn main() Int:
    if probe(stdin()): return 1

    return 0

fn read_line(input: ReadStream[Bytes], max_bytes: Int) String?:
    return none

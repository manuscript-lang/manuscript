// conform: tags=control-flow,formatter,modules,optional,parser,stdlib-io,tier-core
// conform: phase=parse
// conform: origin=tests/e2e/fault_locations_test.go:63 TestFaultSourceLocations
import Bytes from "@std/bytes.ms"
import ReadStream, stdin from "@std/io/io.ms"

fn limit() Int:
    return 1 / "".byte_length()

fn probe(input: ReadStream[Bytes]) Bool:
    if let line = read_line(input, limit()):
        return line.length() > 0

    return false

export fn main() Int:
    if probe(stdin()): return 1

    return 0

fn read_line(input: ReadStream[Bytes], max_bytes: Int) String?:
    return none

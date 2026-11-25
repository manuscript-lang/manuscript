// conform: tags=control-flow,formatter,modules,optional,stdlib-io,tier-core
// conform: phase=run,parse
// conform: origin=tests/e2e/fault_locations_test.go:63 TestFaultSourceLocations
import (
	Bytes from "@std/bytes.ms",
	ReadStream, stdin from "@std/io/io.ms",
)

fn limit() Int {
	return 1 / "".length()
}

fn probe(input ReadStream[Bytes]) Bool {
	line := read_line(input, limit())
	if line != null { return not line.is_empty() }

	return false
}

export fn main() Int {
	if probe(stdin()) { return 1 }
	return 0
}

fn read_line(input ReadStream[Bytes], max_bytes Int) String? {
	return null
}
// expect-exit: 134
// expect-stderr: division by zero; right must be nonzero, found 0
// expect-stderr:   at testfaultsourcelocations-5.ms:10 in limit
// expect-stderr:   at testfaultsourcelocations-5.ms:14 in probe
// expect-stderr:   at testfaultsourcelocations-5.ms:21 in main

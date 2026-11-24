// conform: tags=faults,formatter,optional,parser,testing,tier-core
// conform: phase=parse
// conform: origin=tests/e2e/e2e_test.go:67 TestRuntimeFaults
import panic from "@std/core.ms"

test "fault":
	missing: Int? := null
	_impossible := missing or panic("called Optional.get() on null")

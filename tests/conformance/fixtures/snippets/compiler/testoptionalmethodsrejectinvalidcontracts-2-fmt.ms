// conform: tags=faults,formatter,optional,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/optional_test.go:65 TestOptionalMethodsRejectInvalidContracts
import panic from "@std/core.ms"

fn wrong(value Int??) Int:
	return value or panic("called Optional.get() on null")

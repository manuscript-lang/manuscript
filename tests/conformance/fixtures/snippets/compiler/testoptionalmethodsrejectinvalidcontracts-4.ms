// conform: tags=alternatives,diagnostics,faults,generics,optional,records,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/optional_test.go:71 TestOptionalMethodsRejectInvalidContracts
import panic from "@std/core.ms"

enum Optional[T]:
	T
	null

fn wrong(value: Int?) Int:
	return value or panic("called Optional.get() on null")

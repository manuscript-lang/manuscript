// conform: tags=alternatives,faults,formatter,generics,optional,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/optional_test.go:71 TestOptionalMethodsRejectInvalidContracts
import panic from "@std/core.ms"

enum Optional[T] {
	T
	null
}

fn wrong(value Int?) Int {
	return value or panic("called Optional.get() on null")
}

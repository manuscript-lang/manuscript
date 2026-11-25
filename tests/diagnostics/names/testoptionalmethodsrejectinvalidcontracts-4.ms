// conform: tags=alternatives,diagnostics,faults,formatter,generics,optional,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/optional_test.go:71 TestOptionalMethodsRejectInvalidContracts
import panic from "@std/core.ms"

enum Optional[T] {
	T
	null
}

fn wrong(value Int?) Int {
	return value or panic("called Optional.get() on null")
}
// expect-error: MS2001 6:1 declaration Optional reuses a prelude name; rename it, because Optional always refers to the standard declaration

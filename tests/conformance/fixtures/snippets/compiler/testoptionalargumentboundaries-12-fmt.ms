// conform: tags=faults,formatter,generics,optional,parser,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/optional_test.go:35 TestOptionalArgumentBoundaries
import panic from "@std/core.ms"

fn f[T](value: T?) T: return value or panic("called Optional.get() on null")

fn call() Void: value := f(null)

// conform: tags=alternatives,diagnostics,generics,optional,records,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/optional_test.go:53 TestOptionalArgumentBoundaries
enum Optional[T]:
    T
    none

fn f(value: Int?) Unit: return

fn call() Unit: f(4)

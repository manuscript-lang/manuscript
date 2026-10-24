# conform: tags=alternatives,diagnostics,generics,optional,records,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/optional_test.go:53 TestOptionalArgumentBoundaries
type Optional[T]:
    case some(value: T)
    case none

def f(value: Optional[Int]) -> Unit: return

def call() -> Unit: f(4)

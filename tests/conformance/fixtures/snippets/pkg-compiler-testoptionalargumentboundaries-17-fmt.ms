# conform: tags=alternatives,formatter,generics,optional,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/optional_test.go:53 TestOptionalArgumentBoundaries
type Optional[T]:
    case some(value: T)
    case none

fn f(value: Optional[Int]) Unit: return

fn call() Unit: f(4)

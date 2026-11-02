# conform: tags=alternatives,formatter,generics,optional,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/optional_test.go:53 TestOptionalArgumentBoundaries
type Optional[T]:
    case T
    case none

fn f(value: Int?) Unit: return

fn call() Unit: f(4)

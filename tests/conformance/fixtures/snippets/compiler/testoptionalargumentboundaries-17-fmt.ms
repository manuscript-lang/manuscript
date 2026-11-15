// conform: tags=alternatives,formatter,generics,optional,parser,records,tier-core
// conform: phase=parse
// conform: origin=pkg/compiler/optional_test.go:53 TestOptionalArgumentBoundaries
enum Optional[T]:
    T
    none

fn f(value: Int?) Void: return

fn call() Void: f(4)

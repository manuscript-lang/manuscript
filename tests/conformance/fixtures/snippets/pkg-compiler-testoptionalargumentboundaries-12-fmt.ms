# conform: tags=faults,formatter,generics,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/optional_test.go:35 TestOptionalArgumentBoundaries
def f[T](value: Optional[T]) -> T: return value.get()

def call() -> Unit: let value = f(none)

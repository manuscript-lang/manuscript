# conform: tags=formatter,generics,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/optional_test.go:34 TestOptionalArgumentBoundaries
def f[T](value: Optional[T] = none) -> Unit: return

def call() -> Unit: f()

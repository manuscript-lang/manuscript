# conform: tags=diagnostics,generics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/optional_test.go:34 TestOptionalArgumentBoundaries
def f[T](value: Optional[T] = none) -> Unit: return

def call() -> Unit: f()

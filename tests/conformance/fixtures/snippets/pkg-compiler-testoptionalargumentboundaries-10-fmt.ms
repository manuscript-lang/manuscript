# conform: tags=formatter,generics,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/optional_test.go:33 TestOptionalArgumentBoundaries
def f[T](first: Optional[T], second: T) -> Unit: return

def call() -> Unit: f(first: 4, second: "wrong")

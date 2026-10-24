# conform: tags=formatter,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/optional_test.go:39 TestOptionalArgumentBoundaries
def f(value: Optional[Int]) -> Unit: return

def call() -> Unit: f(4, value: 5)

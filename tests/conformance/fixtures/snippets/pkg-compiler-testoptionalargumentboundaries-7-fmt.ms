# conform: tags=formatter,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/optional_test.go:30 TestOptionalArgumentBoundaries
def f(value: Optional[Optional[Int]]) -> Unit: return

def call() -> Unit: f(4)

# conform: tags=formatter,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/optional_test.go:24 TestOptionalArgumentBoundaries
def f(value: Optional[Int]) -> Unit: return

def call() -> Unit: f("wrong")

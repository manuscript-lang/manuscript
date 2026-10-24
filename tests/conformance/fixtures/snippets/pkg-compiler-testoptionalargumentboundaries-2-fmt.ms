# conform: tags=formatter,numbers,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/optional_test.go:25 TestOptionalArgumentBoundaries
def f(value: Optional[Float]) -> Unit: return

def call() -> Unit: f(4)

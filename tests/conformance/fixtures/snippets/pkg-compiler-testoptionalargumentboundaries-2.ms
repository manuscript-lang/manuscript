# conform: tags=diagnostics,numbers,optional,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/optional_test.go:25 TestOptionalArgumentBoundaries
def f(value: Optional[Float]) -> Unit: return

def call() -> Unit: f(4)

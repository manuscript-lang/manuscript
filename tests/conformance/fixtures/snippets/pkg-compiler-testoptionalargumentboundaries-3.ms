# conform: tags=diagnostics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/optional_test.go:26 TestOptionalArgumentBoundaries
def f(value: Optional[Int]) -> Unit: return

def call() -> Unit: f()

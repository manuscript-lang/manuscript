# conform: tags=diagnostics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/optional_test.go:38 TestOptionalArgumentBoundaries
def f(value: Optional[Int]) -> Unit: return

def call() -> Unit: f(other: 4)

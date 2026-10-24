# conform: tags=diagnostics,numbers,optional,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/optional_test.go:32 TestOptionalArgumentBoundaries
def f(value: Optional[Float]) -> Unit: return

def call(value: Optional[Int]) -> Unit: f(value)

# conform: tags=diagnostics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/optional_test.go:31 TestOptionalArgumentBoundaries
def f(value: Int) -> Unit: return

def call() -> Unit: f(some(value: 4))

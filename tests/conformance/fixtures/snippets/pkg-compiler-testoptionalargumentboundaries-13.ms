# conform: tags=diagnostics,lists,optional,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/optional_test.go:36 TestOptionalArgumentBoundaries
def f(values: List[Optional[Int]]) -> Unit: return

def call() -> Unit: f([4])

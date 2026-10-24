# conform: tags=formatter,lists,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/optional_test.go:36 TestOptionalArgumentBoundaries
def f(values: List[Optional[Int]]) -> Unit: return

def call() -> Unit: f([4])

# conform: tags=diagnostics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/optional_test.go:29 TestOptionalArgumentBoundaries
def f(value: Optional[Int] = 4) -> Unit: return

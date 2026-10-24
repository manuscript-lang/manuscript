# conform: tags=formatter,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/optional_test.go:29 TestOptionalArgumentBoundaries
def f(value: Optional[Int] = 4) -> Unit: return

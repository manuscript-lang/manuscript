# conform: tags=diagnostics,lists,tier-core
# conform: phase=check
# conform: origin=pkg/build/expression_conveniences_test.go:17 TestExpressionConvenienceRejections
def f() -> Unit: let xs = List[Int](1)

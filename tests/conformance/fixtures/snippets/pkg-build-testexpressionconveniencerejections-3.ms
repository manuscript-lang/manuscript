# conform: tags=diagnostics,lists,tier-core
# conform: phase=check
# conform: origin=pkg/build/expression_conveniences_test.go:14 TestExpressionConvenienceRejections
def f(xs: List[Int]) -> Int: return xs["0"]

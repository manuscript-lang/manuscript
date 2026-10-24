# conform: tags=formatter,lists,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/expression_conveniences_test.go:14 TestExpressionConvenienceRejections
def f(xs: List[Int]) -> Int: return xs["0"]

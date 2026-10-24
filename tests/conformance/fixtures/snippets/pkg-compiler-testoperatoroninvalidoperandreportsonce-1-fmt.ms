# conform: tags=formatter,mutation,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/compiler/conversions_queries_test.go:47 TestOperatorOnInvalidOperandReportsOnce
def f() -> Int:
    var x: Int = 1
    x += try 3
    return x

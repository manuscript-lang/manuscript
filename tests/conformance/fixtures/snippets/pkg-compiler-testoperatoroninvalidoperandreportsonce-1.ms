# conform: tags=diagnostics,mutation,tier-core,try-result
# conform: phase=check
# conform: origin=pkg/compiler/conversions_queries_test.go:47 TestOperatorOnInvalidOperandReportsOnce
fn f() Int:
    var x: Int = 1
    x += try 3
    return x

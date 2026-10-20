# conform: tags=match,optional,parser,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/parser/diagnostics_test.go:48 TestUnsupportedPatternAndNamespaceDiagnostics
fn f(r: Result[Optional[Int], String]) Int:
    match r:
        ok(some(n)): return n
    return 0

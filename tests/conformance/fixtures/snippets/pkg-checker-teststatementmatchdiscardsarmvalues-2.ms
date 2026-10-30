# conform: tags=diagnostics,lists,match,mutation,optional,tier-core
# conform: phase=check
# conform: origin=pkg/checker/diagnostic_fixes_test.go:76 TestStatementMatchDiscardsArmValues
fn f(var xs: List[Int], o: Int?) Unit:
    var n = 0

    match o:
        some(v):
            n = v
            xs.set(index: 0, value: 5)
        none:
            n = 2

    xs.append(n)

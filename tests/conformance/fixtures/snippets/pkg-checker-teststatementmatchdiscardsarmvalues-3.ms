# conform: tags=diagnostics,lists,match,optional,tier-core
# conform: phase=check
# conform: origin=pkg/checker/diagnostic_fixes_test.go:77 TestStatementMatchDiscardsArmValues
fn f(xs: List[Int], o: Int?) Unit:
    let r = match o:
        some(v):
            xs.set(index: 0, value: v)
        none:
            xs.length()

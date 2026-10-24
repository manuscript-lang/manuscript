# conform: tags=diagnostics,lists,match,mutation,optional,tier-core
# conform: phase=check
# conform: origin=pkg/checker/diagnostic_fixes_test.go:76 TestStatementMatchDiscardsArmValues
def f(var xs: List[Int], o: Optional[Int]) -> Unit:
    var n = 0

    match o:
        case some(v):
            n = v
            xs.set(index: 0, value: 5)
        case none:
            n = 2

    xs.append(n)

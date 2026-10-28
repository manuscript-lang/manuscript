# conform: tags=formatter,lists,match,mutation,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/diagnostic_fixes_test.go:76 TestStatementMatchDiscardsArmValues
fn f(var xs: List[Int], o: Optional[Int]) Unit:
    var n = 0

    match o:
        some(v):
            n = v
            xs.set(index: 0, value: 5)
        none:
            n = 2

    xs.append(n)

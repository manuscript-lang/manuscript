# conform: tags=formatter,lists,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/diagnostic_fixes_test.go:77 TestStatementMatchDiscardsArmValues
fn f(xs: List[Int], o: Optional[Int]) Unit:
    let r = match o:
        some(v):
            xs.set(index: 0, value: v)
        none:
            xs.length()

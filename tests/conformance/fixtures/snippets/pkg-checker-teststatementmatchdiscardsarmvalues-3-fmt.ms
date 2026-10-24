# conform: tags=formatter,lists,match,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/diagnostic_fixes_test.go:77 TestStatementMatchDiscardsArmValues
def f(xs: List[Int], o: Optional[Int]) -> Unit:
    let r = match o:
        case some(v):
            xs.set(index: 0, value: v)
        case none:
            xs.length()

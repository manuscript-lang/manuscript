# conform: tags=mutation,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/hints_test.go:25 TestSyntaxErrorsStateTheFix
fn f() Int:
    var i = 0
    i--
    return i

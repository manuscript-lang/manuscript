# conform: tags=closures,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/hints_test.go:31 TestSyntaxErrorsStateTheFix
fn f() Int:
    let n = [1].map(fn(x) => x + 1)
    return 0

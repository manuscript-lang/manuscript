# conform: tags=control-flow,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:213 TestInlineSuites
fn f() Unit:
    if true: use() else if false: use()

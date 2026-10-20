# conform: tags=control-flow,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:216 TestInlineSuites
fn f() Unit:
    if true: return
        return

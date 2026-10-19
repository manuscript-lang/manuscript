# conform: tags=control-flow,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:212 TestInlineSuites
fn f() Unit:
    if true: return else: return

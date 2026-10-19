# conform: tags=control-flow,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:242 TestContextualCallbackRecovery
fn f() Unit:
    if true: 1

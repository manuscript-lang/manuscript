# conform: tags=control-flow,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:211 TestInlineSuites
fn f(x: Int) Int:
    if x > 0: return x else: return 0

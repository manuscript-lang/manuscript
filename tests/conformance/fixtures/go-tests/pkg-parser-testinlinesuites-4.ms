# conform: tags=control-flow,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/parser/parser_test.go:201 TestInlineSuites
fn f(x: Int) Int:
    if x > 0: return x
    else if x == 0: return 1
    else:
        return 2

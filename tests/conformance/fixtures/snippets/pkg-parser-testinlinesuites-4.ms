# conform: tags=control-flow,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/parser/parser_test.go:201 TestInlineSuites
def f(x: Int) -> Int:
    if x > 0: return x
    elif x == 0: return 1
    else:
        return 2

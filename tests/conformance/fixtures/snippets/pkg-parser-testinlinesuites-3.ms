# conform: tags=control-flow,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/parser/parser_test.go:200 TestInlineSuites
def f(x: Int) -> Int:
    if x > 0: return x
    else: return 0

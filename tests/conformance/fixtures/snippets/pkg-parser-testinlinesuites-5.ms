# conform: tags=control-flow,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/parser/parser_test.go:202 TestInlineSuites
def f() -> Unit:
    if True:
        return
    else: return

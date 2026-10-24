# conform: tags=control-flow,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:202 TestInlineSuites
def f() -> Unit:
    if True:
        return
    else: return

# conform: tags=control-flow,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:201 TestInlineSuites
def f(x: Int) -> Int:
    if x > 0: return x
    elif x == 0: return 1
    else:
        return 2

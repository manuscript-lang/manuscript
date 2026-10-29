# conform: tags=control-flow,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:201 TestInlineSuites
fn f(x: Int) Int:
    if x > 0: return x
    else if x == 0: return 1
    else:
        return 2

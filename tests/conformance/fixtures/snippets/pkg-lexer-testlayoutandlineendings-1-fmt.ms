# conform: tags=control-flow,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/lexer/lexer_test.go:14 TestLayoutAndLineEndings
# module
def value() -> Int:
    # comment
    if True:
        return 3
    else:
        return 4

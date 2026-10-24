# conform: tags=control-flow,diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/lexer/lexer_test.go:14 TestLayoutAndLineEndings
# module
def value() -> Int:
    # comment
    if True:
        return 3
    else:
        return 4

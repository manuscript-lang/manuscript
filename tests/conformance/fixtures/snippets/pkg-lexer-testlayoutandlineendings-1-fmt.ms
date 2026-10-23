# conform: tags=control-flow,formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/lexer/lexer_test.go:14 TestLayoutAndLineEndings
# module
fn value() Int:
    # comment
    if true:
        return 3
    else:
        return 4

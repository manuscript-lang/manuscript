# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/lexer/lexer_test.go:171 TestTrailingPipeOverIndentHint
fn f() Int:
    let a = 1 |
        g
    return a

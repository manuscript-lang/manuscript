# conform: tags=control-flow,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/partial_test.go:178 TestPartialOmitsDeclarationWhenInvalidStatementIsAnEntireBlock
fn a() Int:
    if true:
        let y = = 3
    return 1

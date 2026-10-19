# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/partial_test.go:171 TestPartialOmitsDeclarationWithInvalidSignature
fn broken(a: ) Int:
    return 1
fn ok() Int:
    return 2

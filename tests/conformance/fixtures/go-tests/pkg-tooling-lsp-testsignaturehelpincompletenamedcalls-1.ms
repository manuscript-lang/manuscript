# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/features_test.go:24 TestSignatureHelpIncompleteNamedCalls
# Add two numbers.
fn sum(left: Int, right: Int) Int:
    return left + right
fn answer() Int:
    return sum(left: 1, ri|

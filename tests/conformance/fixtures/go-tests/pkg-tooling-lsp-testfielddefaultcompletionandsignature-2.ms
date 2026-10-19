# conform: tags=parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/defaults_test.go:108 TestFieldDefaultCompletionAndSignature
type Options:
    required: Int
    count: Int = 3
fn read() Options:
    return Options(required: 1, |)

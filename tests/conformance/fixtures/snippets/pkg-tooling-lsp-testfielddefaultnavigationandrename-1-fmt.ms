# conform: tags=formatter,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/defaults_test.go:81 TestFieldDefaultNavigationAndRename
type Options:
    first: Int = 3
    second: Int = first + 1
fn read() Int: return Options().first

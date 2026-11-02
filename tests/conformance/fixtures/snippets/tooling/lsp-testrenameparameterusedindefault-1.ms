# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/defaults_test.go:66 TestRenameParameterUsedInDefault
fn combine(first: Int = 3, second: Int = first) Int:
    return first + second

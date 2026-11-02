# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/analysis_test.go:112 TestLocalRenameUsesBindingsAndVersions
fn answer() Int:
    let number = 42
    return number

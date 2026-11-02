# conform: tags=control-flow,diagnostics,lists,tier-core
# conform: phase=check
# conform: origin=pkg/tooling/lsp/if_let_test.go:9 TestIfLetBindingReferencesAndRename
fn read(values: List[Int]) Int:
    if let first = values.first():
        return first + 1

    return 0

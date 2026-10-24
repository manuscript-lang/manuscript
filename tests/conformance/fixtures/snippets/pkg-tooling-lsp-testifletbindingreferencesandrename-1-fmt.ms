# conform: tags=control-flow,formatter,lists,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/if_let_test.go:9 TestIfLetBindingReferencesAndRename
def read(values: List[Int]) -> Int:
    if let first = values.first():
        return first + 1

    return 0

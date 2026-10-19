# conform: tags=lists,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/features_test.go:33 TestSignatureHelpIncompleteNamedCalls
fn work(values: List[String]) Unit:
    values.append(value: |

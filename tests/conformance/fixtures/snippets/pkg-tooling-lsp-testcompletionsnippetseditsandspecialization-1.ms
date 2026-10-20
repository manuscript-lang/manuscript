# conform: tags=lists,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:163 TestCompletionSnippetsEditsAndSpecialization
fn count(items: List[String]) Unit:
    items.ap|

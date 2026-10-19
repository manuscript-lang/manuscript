# conform: tags=parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/prelude_imports_test.go:202 TestPreludeTypeCompletionRespectsShadowing
fn use[ListEntry](value: ListE|) Unit:
fn other() Unit: unit

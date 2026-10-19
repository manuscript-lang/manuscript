# conform: tags=closures,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/prelude_imports_test.go:191 TestPreludeTypeCompletionRespectsShadowing
fn use() Unit:
    let ListEntry = fn() Int: 1
    let value: ListE|

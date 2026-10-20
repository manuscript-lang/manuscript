# conform: tags=closures,mutation,parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/prelude_imports_test.go:192 TestPreludeTypeCompletionRespectsShadowing
fn use() Unit:
    let ListEntry = fn() Int: 1
    var value: ListE|

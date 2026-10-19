# conform: tags=parser,tier-core,try-result
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:144 TestTypedCompletionWhileEditing
fn work() Result[Int, Error]:
    return Result[Int, Error].|

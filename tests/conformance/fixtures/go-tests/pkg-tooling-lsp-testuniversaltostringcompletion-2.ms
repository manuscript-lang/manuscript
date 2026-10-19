# conform: tags=generics,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:234 TestUniversalToStringCompletion
fn text[T](value: T) String:
    return value.|

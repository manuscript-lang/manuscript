# conform: tags=interfaces,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/completion_test.go:235 TestUniversalToStringCompletion
interface Named:
    fn name() String
fn text(value: Named) String:
    return value.|

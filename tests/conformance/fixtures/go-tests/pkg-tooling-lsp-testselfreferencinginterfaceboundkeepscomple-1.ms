# conform: tags=generics,interfaces,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/bound_recovery_test.go:27 TestSelfReferencingInterfaceBoundKeepsCompletion
interface Compare[T]:
    fn compare(other: T) Int
fn compare[T: Compare[T]](first: T, second: T) Int: first.|

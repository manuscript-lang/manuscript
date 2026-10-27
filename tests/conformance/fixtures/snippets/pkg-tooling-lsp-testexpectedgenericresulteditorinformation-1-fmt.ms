# conform: tags=closures,formatter,generics,optional,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/contextual_generics_test.go:10 TestExpectedGenericResultEditorInformation
def absent[T]() -> Optional[T]: none

def transform[T, U](callback: Callable[[T], U]) -> Callable[[T], U]: callback

def answer() -> Unit:
    let _empty: Optional[Int] = absent()
    let _callback: Callable[[Int], String] = transform(lambda item: item.to_string())

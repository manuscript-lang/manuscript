# conform: tags=formatter,generics,optional,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/checker/default_type_arguments_test.go:28 TestDefaultTypeArgumentRules
def make[T, U = Int]() -> Optional[T]: none

def use() -> Unit:
    let x = make()

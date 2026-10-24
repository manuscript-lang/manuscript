# conform: tags=diagnostics,generics,optional,tier-core
# conform: phase=check
# conform: origin=pkg/checker/default_type_arguments_test.go:28 TestDefaultTypeArgumentRules
def make[T, U = Int]() -> Optional[T]: none

def use() -> Unit:
    let x = make()

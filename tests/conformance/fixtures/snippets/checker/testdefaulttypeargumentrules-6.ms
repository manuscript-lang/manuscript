// conform: tags=diagnostics,generics,optional,tier-core
// conform: phase=check
// conform: origin=pkg/checker/default_type_arguments_test.go:28 TestDefaultTypeArgumentRules
fn make[T, U = Int]() T? => null

fn use() Void:
    x := make()

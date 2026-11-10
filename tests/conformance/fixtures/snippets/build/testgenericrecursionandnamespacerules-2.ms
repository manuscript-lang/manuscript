// conform: tags=diagnostics,generics,lists,tier-core
// conform: phase=check
// conform: origin=pkg/build/compiler_test.go:257 TestGenericRecursionAndNamespaceRules
fn recurse[T](value: T) Unit:
    next := recurse[List[T]]

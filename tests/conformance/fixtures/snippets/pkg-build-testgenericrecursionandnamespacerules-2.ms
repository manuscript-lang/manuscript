# conform: tags=diagnostics,generics,lists,tier-core
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:257 TestGenericRecursionAndNamespaceRules
def recurse[T](value: T) -> Unit:
    let next = recurse[List[T]]

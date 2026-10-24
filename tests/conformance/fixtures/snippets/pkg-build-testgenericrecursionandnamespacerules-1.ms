# conform: tags=diagnostics,generics,tier-core
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:256 TestGenericRecursionAndNamespaceRules
def recurse[T](value: T) -> Unit:
    recurse(value: [value])

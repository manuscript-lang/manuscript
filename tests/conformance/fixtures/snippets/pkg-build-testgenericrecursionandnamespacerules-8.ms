# conform: tags=control-flow,diagnostics,generics,tier-core
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:271 TestGenericRecursionAndNamespaceRules
def recurse[T](value: T, count: Int) -> T:
    if count == 0:
        return value

    return recurse(value: value, count: count - 1)

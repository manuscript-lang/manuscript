# conform: tags=control-flow,formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:271 TestGenericRecursionAndNamespaceRules
fn recurse[T](value: T, count: Int) T:
    if count == 0:
        return value
    return recurse(value: value, count: count - 1)

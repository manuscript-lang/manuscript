# conform: tags=formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:256 TestGenericRecursionAndNamespaceRules
fn recurse[T](value: T) Unit:
    recurse(value: [value])

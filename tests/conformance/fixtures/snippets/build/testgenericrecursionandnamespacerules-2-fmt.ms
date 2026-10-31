# conform: tags=formatter,generics,lists,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:257 TestGenericRecursionAndNamespaceRules
fn recurse[T](value: T) Unit:
    let next = recurse[List[T]]

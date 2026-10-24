# conform: tags=formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/recursive_types_test.go:17 TestRecursiveTypesPreserveInitializationAndHashing
def hash[T: Hashable](value: T) -> Int: return value.hash()

def f(node: Node) -> Int: return hash(node)

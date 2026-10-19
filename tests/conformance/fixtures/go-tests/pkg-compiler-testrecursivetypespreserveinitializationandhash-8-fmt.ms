# conform: tags=formatter,generics,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/recursive_types_test.go:17 TestRecursiveTypesPreserveInitializationAndHashing
fn hash[T: Hashable](value: T) Int: return value.hash()
fn f(node: Node) Int: return hash(node)

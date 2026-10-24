# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/recursive_types_test.go:14 TestRecursiveTypesPreserveInitializationAndHashing
def f(node: Node) -> Int: return node.hash()

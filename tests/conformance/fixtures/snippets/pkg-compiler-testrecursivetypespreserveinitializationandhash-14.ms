# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/recursive_types_test.go:47 TestRecursiveTypesPreserveInitializationAndHashing
def compare(left: Node, right: Node) -> Bool: return left == right

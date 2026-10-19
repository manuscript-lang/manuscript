# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/recursive_types_test.go:14 TestRecursiveTypesPreserveInitializationAndHashing
fn f(node: Node) Int: return node.hash()

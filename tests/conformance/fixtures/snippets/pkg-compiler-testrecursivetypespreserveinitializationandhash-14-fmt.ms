# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/recursive_types_test.go:47 TestRecursiveTypesPreserveInitializationAndHashing
fn compare(left: Node, right: Node) Bool: return left == right

# conform: tags=formatter,parser,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/recursive_types_test.go:11 TestRecursiveTypesPreserveInitializationAndHashing
fn f() Unit:
    let node = Node(value: 1, next: node)

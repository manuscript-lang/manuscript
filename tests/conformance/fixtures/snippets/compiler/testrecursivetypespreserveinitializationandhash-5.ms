// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/recursive_types_test.go:14 TestRecursiveTypesPreserveInitializationAndHashing
fn f(node Node) Int => return node.hash()
// expect-error: MS2001 4:11 unknown type Node; declare it with 'type Node:' / 'enum Node:' / 'interface Node:', declare it as a type parameter, or import it

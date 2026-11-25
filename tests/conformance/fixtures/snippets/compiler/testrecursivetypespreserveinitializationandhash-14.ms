// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/recursive_types_test.go:47 TestRecursiveTypesPreserveInitializationAndHashing
fn compare(left Node, right Node) Bool => return left == right
// expect-error: MS2001 4:17 unknown type Node; declare it with 'type Node:' / 'enum Node:' / 'interface Node:', declare it as a type parameter, or import it
// expect-error: MS2001 4:29 unknown type Node; declare it with 'type Node:' / 'enum Node:' / 'interface Node:', declare it as a type parameter, or import it

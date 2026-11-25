// conform: tags=diagnostics,maps,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/recursive_types_test.go:15 TestRecursiveTypesPreserveInitializationAndHashing
fn f(values Map[Node, Int]) Void => return
// expect-error: MS2001 4:17 unknown type Node; declare it with 'type Node:' / 'enum Node:' / 'interface Node:', declare it as a type parameter, or import it

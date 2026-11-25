// conform: tags=diagnostics,formatter,sets,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/recursive_types_test.go:16 TestRecursiveTypesPreserveInitializationAndHashing
fn f(values Set[Node]) Void => return
// expect-error: MS2001 4:17 unknown type Node; declare it with 'type Node:' / 'enum Node:' / 'interface Node:', declare it as a type parameter, or import it

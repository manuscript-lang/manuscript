// conform: tags=diagnostics,formatter,generics,tier-core
// conform: phase=check,parse
// conform: origin=pkg/compiler/recursive_types_test.go:17 TestRecursiveTypesPreserveInitializationAndHashing
fn hash[T Hashable](value T) Int => return value.hash()

fn f(node Node) Int => return hash(node)
// expect-error: MS2001 6:11 unknown type Node; declare it with 'type Node:' / 'enum Node:' / 'interface Node:', declare it as a type parameter, or import it

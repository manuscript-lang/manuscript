// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/interface_hints_test.go:21 TestInterfaceAndReceiverHints
fn area(shape Shape) Int => shape.area()

fn run() Int => area(Sq(2))
// expect-error: MS2001 4:15 unknown type Shape; declare it with 'type Shape:' / 'enum Shape:' / 'interface Shape:', declare it as a type parameter, or import it
// expect-error: MS2001 6:22 unknown binding Sq; declare it with 'Sq := ...' before use, define 'fn Sq(...) T { ... }', or import it from a module

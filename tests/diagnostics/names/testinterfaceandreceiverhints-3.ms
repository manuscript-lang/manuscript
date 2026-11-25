// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/interface_hints_test.go:19 TestInterfaceAndReceiverHints
fn shape() Shape => Sq(2)
// expect-error: MS2001 4:12 unknown type Shape; declare it with 'type Shape:' / 'enum Shape:' / 'interface Shape:', declare it as a type parameter, or import it
// expect-error: MS2001 4:21 unknown binding Sq; declare it with 'Sq := ...' before use, define 'fn Sq(...) T { ... }', or import it from a module

// conform: tags=diagnostics,formatter,lists,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/interface_hints_test.go:20 TestInterfaceAndReceiverHints
fn shapes() List[Shape] => [Sq(2)]
// expect-error: MS2001 4:18 unknown type Shape; declare it with 'type Shape:' / 'enum Shape:' / 'interface Shape:', declare it as a type parameter, or import it
// expect-error: MS2001 4:29 unknown binding Sq; declare it with 'Sq := ...' before use, define 'fn Sq(...) T { ... }', or import it from a module

// conform: tags=diagnostics
// conform: phase=check
fn area(shape Shape) Int => shape.area()

fn run() Int => area(Sq(2))
// expect-error: MS2001 3:15 unknown type Shape; declare it with 'type Shape:' / 'enum Shape:' / 'interface Shape:', declare it as a type parameter, or import it
// expect-error: MS2001 5:22 unknown binding Sq; declare it with 'Sq := ...' before use, define 'fn Sq(...) T { ... }', or import it from a module

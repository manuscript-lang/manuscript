// conform: tags=numbers,types,diagnostics,tier-core
// conform: phase=check
// conform: origin=unsigned integer types stage 1
fn main() Unit:
    a: UInt8 := 256
    b: UInt8 := -1
    c: UInt8 := 5
    d := -c
    e: Int := c
    f: UInt8 := e
    g: UInt16 := c
    h := c + 300
    i: UInt8 := 3 - 5

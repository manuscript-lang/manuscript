// conform: tags=numbers,types,diagnostics,tier-core
// conform: phase=check
// conform: origin=sized numeric types stage 2
fn main() Unit:
    a: Int8 = 1
    b: Int32 = a
    c: Int8 = b.to_int8()
    d: Int16 = a.to_int16().to_int8()
    e: Float32 = a.to_float()
    f := a.to_float32().to_int8()

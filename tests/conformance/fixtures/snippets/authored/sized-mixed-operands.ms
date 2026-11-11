// conform: tags=numbers,types,diagnostics,tier-core
// conform: phase=check
// conform: origin=sized numeric types stage 1
fn main() Unit:
    a: Int32 := 1
    b: Int64 := 2
    mixed := a + b
    plain: Int := 3
    both: Int8 := plain
    rem: Float32 := 1.5
    bad := rem % rem

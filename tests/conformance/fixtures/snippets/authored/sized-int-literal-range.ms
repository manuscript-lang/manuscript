// conform: tags=numbers,types,diagnostics,tier-core
// conform: phase=check
// conform: origin=sized numeric types stage 1
fn main() Unit:
    too_big: Int8 = 128
    too_small: Int8 = -129
    wide: Int32 = 3000000000
    hot: Float32 = 1e39

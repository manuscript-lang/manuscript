# conform: tags=numbers,types,diagnostics,tier-core
# conform: phase=check
# conform: origin=sized numeric types stage 1
def main() -> Unit:
    let too_big: Int8 = 128
    let too_small: Int8 = -129
    let wide: Int32 = 3000000000
    let hot: Float32 = 1e39

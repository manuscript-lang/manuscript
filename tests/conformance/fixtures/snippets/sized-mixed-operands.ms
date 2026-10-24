# conform: tags=numbers,types,diagnostics,tier-core
# conform: phase=check
# conform: origin=sized numeric types stage 1
def main() -> Unit:
    let a: Int32 = 1
    let b: Int64 = 2
    let mixed = a + b
    let plain: Int = 3
    let both: Int8 = plain
    let rem: Float32 = 1.5
    let bad = rem % rem

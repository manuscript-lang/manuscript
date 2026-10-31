# conform: tags=numbers,types,faults,tier-core
# conform: phase=run
# conform: origin=sized numeric types stage 1
export fn main() Int:
    let low: Int8 = -128
    let _flipped = -low
    return 0

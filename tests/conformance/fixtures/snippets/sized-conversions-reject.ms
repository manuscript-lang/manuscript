# conform: tags=numbers,types,diagnostics,tier-core
# conform: phase=check
# conform: origin=sized numeric types stage 2
def main() -> Unit:
    let a: Int8 = 1
    let b: Int32 = a
    let c: Int8 = b.to_int8()
    let d: Int16 = a.to_int16().to_int8()
    let e: Float32 = a.to_float()
    let f = a.to_float32().to_int8()

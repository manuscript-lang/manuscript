# conform: tags=numbers,types,diagnostics,tier-core
# conform: phase=check
# conform: origin=unsigned integer types stage 1
def main() -> Unit:
    let a: UInt8 = 256
    let b: UInt8 = -1
    let c: UInt8 = 5
    let d = -c
    let e: Int = c
    let f: UInt8 = e
    let g: UInt16 = c
    let h = c + 300
    let i: UInt8 = 3 - 5

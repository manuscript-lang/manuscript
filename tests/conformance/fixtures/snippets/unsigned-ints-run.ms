# conform: tags=numbers,types,tier-core
# conform: phase=run
# conform: origin=unsigned integer types stage 1
from "@std/io.ms" import stdout

type Pixel:
    r: UInt8
    g: UInt16
    x: UInt32

def total(values: List[UInt8]) -> UInt8:
    var sum: UInt8 = 0
    for v in values:
        sum = sum + v
    return sum

export def main() -> Int:
    let low: UInt8 = 0
    let high: UInt8 = 255
    let mid: UInt16 = 65535
    let wide: UInt32 = 4000000000
    let _ = stdout().write(f"{low} {high} {mid} {wide}\n")
    let p = Pixel(r: 250, g: 60000, x: 3000000000)
    let _ = stdout().write(f"{p.r} {p.g} {p.x}\n")
    let l: List[UInt8] = [200, 1, 255, 3]
    let _ = stdout().write(f"{l.sorted()} {total([100, 20, 7])}\n")
    let _ = stdout().write(f"{high / 2} {high % 10} {low < high} {wide > 3000000000}\n")
    let opt: Optional[UInt8] = 255
    let big: Int = 300
    let _ = stdout().write(f"{opt.get(0)} {big.to_uint8()} {big.to_uint16()} {wide.to_int32()} {wide.to_int64()}\n")
    let _ = stdout().write(f"{high.to_int()} {mid.to_uint8()} {wide.to_string_radix(16)} {high.compare(low)}\n")
    let _ = stdout().write(f"{wide.to_float()} {high.to_float32()}\n")
    return 0

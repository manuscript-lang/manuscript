# conform: tags=numbers,types,tier-core
# conform: phase=run
# conform: origin=unsigned integer types stage 2
from "@std/io.ms" import stdout

type Stamp:
    id: UInt64
    tag: UInt8

def mix(h: UInt64, b: UInt64) -> UInt64:
    return (h * 31 + b) % 18446744073709551557

export def main() -> Int:
    let max: UInt64 = 18446744073709551615
    let half: UInt64 = 9223372036854775808
    let one: UInt64 = 1
    let _ = stdout().write(f"{max} {half} {one}\n")
    let _ = stdout().write(
        f"{max > half} {half > one} {one < max} {max >= max} {half <= one} {max == max}\n"
    )
    let _ = stdout().write(
        f"{max / 2} {max % 10} {half - 1 + half == max} {max - half}\n"
    )
    let _ = stdout().write(
        f"{max.compare(one)} {one.compare(max)} {half.to_string_radix(16)} {max.to_string_radix(2).length()}\n"
    )
    let _ = stdout().write(
        f"{max.to_float()} {half.to_decimal()} {max.to_int()} {one.to_int()} {max.to_uint32()} {one.to_uint8()}\n"
    )
    let l: List[UInt64] = [max, 5, half, 0]
    let _ = stdout().write(f"{l.sorted()} {l.sorted().reverse()}\n")
    let s = Stamp(id: max, tag: 7)
    let big: Int = 5
    let _ = stdout().write(f"{s.id} {s.tag} {big.to_uint64()} {(-big).to_uint64()}\n")
    var h: UInt64 = 7
    for i in 0..10:
        h = mix(h, i.to_uint64().get(0))

    let _ = stdout().write(f"{h}\n")
    return 0

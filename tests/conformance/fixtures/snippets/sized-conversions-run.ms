# conform: tags=numbers,types,tier-core
# conform: phase=run
# conform: origin=sized numeric types stage 2
import stdout from "@std/io.ms"

export fn main() Int:
    let a: Int8 = -100
    let b: Int32 = 70000
    let big: Int = 5000000000
    let _ = stdout().write(
        "{a.to_int32() + b} {a.to_int64()} {b.to_int8()} {b.to_int16()} {big.to_int32()} {big.to_int64()}\n"
    )
    let _ = stdout().write(
        "{a.to_float()} {b.to_float32()} {big.to_float32()} {a.compare(-99)} {b.to_string_radix(16)}\n"
    )
    let f: Float32 = 0.1
    let g: Float = 0.1
    let _ = stdout().write(
        "{f.to_float64()} {g.to_float32()} {f.is_nan()} {f.compare(f)} {f.truncate_to_int()} {(2.5).to_float32()}\n"
    )
    let _ = stdout().write("{a.to_decimal()}\n")
    return 0

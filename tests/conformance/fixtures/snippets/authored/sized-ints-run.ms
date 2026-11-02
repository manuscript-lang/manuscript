# conform: tags=numbers,types,tier-core
# conform: phase=run
# conform: origin=sized numeric types stage 1
import stdout from "@std/io/io.ms"

fn total(values: List[Int8]) Int8:
    var sum: Int8 = 0
    for v in values:
        sum = sum + v
    return sum

export fn main() Int:
    let low: Int8 = -128
    let high: Int8 = 127
    let wide: Int32 = 2000000000
    let mid: Int16 = -32768
    let same: Int64 = 9000000000
    let half: Float32 = 0.1
    let other: Float32 = 0.2
    let exact: Float64 = 0.1
    let exact_other: Float64 = 0.2
    let _ = stdout().write("{low} {high} {wide} {mid} {same}\n")
    let _ = stdout().write("{half + other} {exact + exact_other}\n")
    let _ = stdout().write("{total([100, 20, 7])} {low / 2} {high % 10} {-high}\n")
    let _ = stdout().write("{low < high} {wide == wide} {half == half}\n")
    return 0

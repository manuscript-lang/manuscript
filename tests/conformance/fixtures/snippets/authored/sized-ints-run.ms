// conform: tags=numbers,types,tier-core
// conform: phase=run
// conform: origin=sized numeric types stage 1
import stdout from "@std/io/io.ms"

fn total(values List[Int8]) Int8:
    var sum Int8 = 0
    for v in values:
        sum = sum + v
    return sum

fn main() Void:
    low Int8 := -128
    high Int8 := 127
    wide Int32 := 2000000000
    mid Int16 := -32768
    same Int64 := 9000000000
    half Float32 := 0.1
    other Float32 := 0.2
    exact Float64 := 0.1
    exact_other Float64 := 0.2
    void stdout().write(f"{low} {high} {wide} {mid} {same}\n")
    void stdout().write(f"{half + other} {exact + exact_other}\n")
    void stdout().write(f"{total([100, 20, 7])} {low / 2} {high % 10} {-high}\n")
    void stdout().write(f"{low < high} {wide == wide} {half == half}\n")

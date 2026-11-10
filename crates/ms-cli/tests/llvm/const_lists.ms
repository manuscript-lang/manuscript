import stdout from "@std/io/io.ms"

// The test replaces each placeholder list with 100 constants.
fn main() Unit:
    var o = stdout()
    a: List[Int] = [100]
    b: List[Int8] = [101]
    c: List[UInt8] = [102]
    d: List[Float] = [3.5]
    e: List[Float32] = [4.5]
    f: List[Bool] = [true]
    var ti = 0
    for x in a: ti += x

    var tb = 0
    for x in b: tb += x.to_int()

    var tc = 0
    for x in c: tc += x.to_int()

    var td = 0.0
    for x in d: td += x

    var te = 0.0
    for x in e: te += x.to_float()

    var tf = 0
    for x in f:
        if x: tf += 1
    o.write("{ti} {tb} {tc} {td} {te} {tf} {a[99]} {b[1]} {f[99]}\n").get()

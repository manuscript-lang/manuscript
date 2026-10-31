import stdout from "@std/io.ms"
import monotonic from "@std/time.ms"

fn say(text: String) Unit:
    let _ignored = stdout().write(text)

fn k_fma(a: List[Float32], b: List[Float32], var out: List[Float32], n: Int) Unit:
    for i in 0..n:
        out[i] = a[i] * b[i] + 1.5

fn k_scale64(a: List[Float], var out: List[Float], n: Int) Unit:
    for i in 0..n:
        out[i] = a[i] * 2.0

fn k_intadd(a: List[Int], b: List[Int], var out: List[Int], n: Int) Unit:
    for i in 0..n:
        out[i] = a[i] + b[i]

fn k_stencil(a: List[Float32], var out: List[Float32], n: Int) Unit:
    for i in 0..n - 1:
        out[i] = a[i] + a[i + 1]

fn k_base(
    w: List[Float32],
    x: List[Float32],
    var out: List[Float32],
    base: Int,
    n: Int
) Unit:
    for i in 0..n:
        out[i] = w[base + i] * x[i]

fn k_clamp(a: List[Float32], var out: List[Float32], n: Int) Unit:
    for i in 0..n:
        let v = a[i]
        out[i] = if v < 0.0: 0.0 else: (if v > 1.0: 1.0 else: v)

fn k_conv(a: List[Int], var out: List[Float], n: Int) Unit:
    for i in 0..n:
        out[i] = a[i].to_float() * 0.5

fn k_dot(a: List[Float32], b: List[Float32], n: Int) Float32:
    var acc: Float32 = 0.0
    for i in 0..n:
        acc = acc + a[i] * b[i]
    return acc

fn report(name: String, flops: Int, reps: Int, t: Int) Unit:
    say("{name} {(flops * reps).to_float() / t.to_float()}\n")

export fn main() Int:
    let n = 4096
    var f1 = List[Float32]()
    var f2 = List[Float32]()
    var fo = List[Float32]()
    var d1 = List[Float]()
    var d2 = List[Float]()
    var i1 = List[Int]()
    var i2 = List[Int]()
    var io = List[Int]()

    for k in 0..n + 8:
        f1.append((k % 7).to_float32() * 0.25 - 0.5)
        f2.append((k % 5).to_float32() * 0.5)
        fo.append(0.0)
        d1.append((k % 7).to_float() * 0.25)
        d2.append(0.0)
        i1.append(k % 11)
        i2.append(k % 13)
        io.append(0)

    let reps = 100000
    var t = monotonic()
    for _r in 0..reps:
        k_fma(f1, f2, var fo, n)
    report("fma32", 2 * n, reps, monotonic().difference(t).to_nanoseconds())
    t = monotonic()
    for _r in 0..reps:
        k_scale64(d1, var d2, n)
    report("scale64", n, reps, monotonic().difference(t).to_nanoseconds())
    t = monotonic()
    for _r in 0..reps:
        k_intadd(i1, i2, var io, n)
    report("intadd", n, reps, monotonic().difference(t).to_nanoseconds())
    t = monotonic()
    for _r in 0..reps:
        k_stencil(f1, var fo, n)
    report("stencil", n, reps, monotonic().difference(t).to_nanoseconds())
    t = monotonic()
    for _r in 0..reps:
        k_base(f1, f2, var fo, 8, n)
    report("base", n, reps, monotonic().difference(t).to_nanoseconds())
    t = monotonic()
    for _r in 0..reps:
        k_clamp(f1, var fo, n)
    report("clamp", n, reps, monotonic().difference(t).to_nanoseconds())
    t = monotonic()
    for _r in 0..reps:
        k_conv(i1, var d2, n)
    report("conv", n, reps, monotonic().difference(t).to_nanoseconds())
    t = monotonic()

    var s: Float32 = 0.0
    for _r in 0..reps:
        s = s + k_dot(f1, f2, n)
    report("dot32", 2 * n, reps, monotonic().difference(t).to_nanoseconds())
    say("check {fo[5]} {d2[5]} {io[5]} {s}\n")
    return 0

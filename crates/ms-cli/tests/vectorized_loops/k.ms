export fn fma(a: List[Float32], b: List[Float32], var out: List[Float32], n: Int) Unit:
    for i in 0..n:
        out[i] = a[i] * b[i] + 1.5

export fn scale(a: List[Float], var out: List[Float], n: Int) Unit:
    for i in 0..n:
        out[i] = a[i] * 2.0

export fn main() Int:
    let a: List[Float] = [1.0, 2.0, 3.0]
    var o: List[Float] = [0.0, 0.0, 0.0]
    scale(a, var o, 3)

    let f: List[Float32] = [1.0, 2.0]
    var h: List[Float32] = [0.0, 0.0]
    fma(f, f, var h, 2)
    return 0

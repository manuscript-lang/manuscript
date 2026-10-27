export def scale(a: List[Float], var out: List[Float], n: Int) -> Unit:
    for i in 0..n:
        out[i] = a[i] * 2.0

export def main() -> Int:
    let a: List[Float] = [1.0, 2.0, 3.0]
    var o: List[Float] = [0.0, 0.0, 0.0]
    scale(a, var o, 4)
    return 0

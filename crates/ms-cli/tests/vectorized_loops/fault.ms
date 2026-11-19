export fn scale(a: List[Float], var out: List[Float], n: Int) Void:
    for i in 0..n:
        out[i] = a[i] * 2.0

fn main() Void:
    a: List[Float] := [1.0, 2.0, 3.0]
    var o: List[Float] = [0.0, 0.0, 0.0]
    scale(a, o, 4)

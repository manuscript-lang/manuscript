from "@std/io.ms" import stdout
from "@std/time.ms" import clock
from "@std/vec.ms" import Matrix

def say(text: String) -> Unit:
    let _ignored = stdout().write(text)

# The matrix-vector product as a plain loop, for comparison with `Matrix.matvec`.
def scalar_matvec(
    w: List[Float32],
    x: List[Float32],
    rows: Int,
    cols: Int,
    var out: List[Float32]
) -> Unit:
    var r = 0

    while r < rows:
        var acc: Float32 = 0.0
        let base = r * cols
        var c = 0

        while c < cols:
            acc = acc + w[base + c] * x[c]
            c += 1

        out[r] = acc
        r += 1

def run(rows: Int, cols: Int, reps: Int) -> Unit:
    var w = List[Float32]()
    var x = List[Float32]()
    for k in 0..rows * cols:
        w.append(((k % 17) - 8).to_float32() * 0.01)
    for k in 0..cols:
        x.append((k % 5).to_float32() * 0.1)

    let flops = (2 * rows * cols * reps).to_float()
    let m = Matrix(rows: rows, cols: cols, data: w.clone())
    var out = List[Float32]()
    let t = clock().now()
    for _r in 0..reps:
        m.matvec(x, var out)

    let ns = clock().now().difference(t).to_nanoseconds().to_float()
    say(f"vec {rows}x{cols} {flops / ns} {out[0]}\n")

    let scalar_reps = reps / 10 if reps >= 10 else 1

    var plain = List[Float32]()
    for _k in 0..rows:
        plain.append(0.0)

    let t2 = clock().now()
    for _r in 0..scalar_reps:
        scalar_matvec(w, x, rows, cols, var plain)

    let ns2 = clock().now().difference(t2).to_nanoseconds().to_float()
    say(
        f"scalar {rows}x{cols} {(2 * rows * cols * scalar_reps).to_float() / ns2} {plain[0]}\n"
    )

export def main() -> Int:
    run(288, 288, 20000)
    run(768, 288, 5000)
    run(4096, 4096, 20)
    return 0

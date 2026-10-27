from "@std/testing.ms" import expect_close, expect_equal, expect_fault, expect_true
from "@std/vec.ms" import Matrix, add_to, argmax, axpy, dot, dot_at, fast_sum, multiply_by, rms_norm, scale, silu, softmax

# Small integers times a power of two, so every partial sum is exact in binary32 and the vector
# kernels must match a left-to-right loop exactly whatever order they add in.
def ramp(n: Int, step: Int) -> List[Float32]:
    var out = List[Float32]()
    for i in 0..n:
        out.append(((i * step) % 23 - 11).to_float32() * 0.25)
    return out

def f32s(values: List[Float]) -> List[Float32]:
    return values.map(lambda x: x.to_float32())

def scalar_dot(
    a: List[Float32],
    a_start: Int,
    b: List[Float32],
    b_start: Int,
    count: Int
) -> Float32:
    var total: Float32 = 0.0
    for i in 0..count:
        total += a[a_start + i] * b[b_start + i]
    return total

test "dot matches a scalar loop for every length around the vector widths":
    for n in 0..70:
        let a = ramp(n, 3)
        let b = ramp(n, 7)
        try expect_equal(dot(a, b), scalar_dot(a, 0, b, 0, n))

test "dot_at reads the requested ranges":
    let a = ramp(100, 5)
    let b = ramp(80, 2)
    for start in [0, 1, 7, 9, 33]:
        try expect_equal(dot_at(a, start, b, 3, 41), scalar_dot(a, start, b, 3, 41))

    let zero: Float32 = 0.0
    try expect_equal(dot_at(a, 100, b, 80, 0), zero)

test "dot_at and dot fault outside their lists":
    let a = ramp(40, 1)
    let _ = try expect_fault(lambda (): let _x = dot_at(a, 1, a, 0, 40))
    let _ = try expect_fault(lambda (): let _x = dot_at(a, -1, a, 0, 8))
    let _ = try expect_fault(lambda (): let _x = dot_at(a, 0, a, 0, -1))
    let _ = try expect_fault(lambda (): let _x = dot(a, ramp(39, 1)))

test "sum matches a scalar loop":
    for n in 0..50:
        let xs = ramp(n, 3)
        var total: Float32 = 0.0
        for x in xs:
            total += x
        try expect_equal(fast_sum(xs), total)

test "argmax and the softmax maximum find the largest element":
    let no_index: Optional[Int] = none
    try expect_equal(argmax(List[Float32]()), no_index)

    for n in 1..40:
        var xs = ramp(n, 5)
        xs[n / 2] = 100.0
        try expect_equal(argmax(xs), some(n / 2))

        # Subtracting the true maximum leaves exp(0) = 1 at its index; any other value would
        # overflow or shrink it.
        softmax(var xs, n)
        try expect_close(xs[n / 2].to_float(), 1.0, 1e-6)

    let nan: Float32 = (0.0 / 0.0).to_float32()
    var with_nan = ramp(20, 1)
    with_nan[3] = nan
    softmax(var with_nan, 20)
    try expect_true(with_nan[0] != with_nan[0])

test "element-wise updates":
    var xs: List[Float32] = [1.0, 2.0, 3.0]
    scale(var xs, 2.0)
    try expect_equal(xs, f32s([2.0, 4.0, 6.0]))
    add_to(var xs, [1.0, 1.0, 1.0])
    try expect_equal(xs, f32s([3.0, 5.0, 7.0]))
    multiply_by(var xs, [2.0, 0.5, 1.0])
    try expect_equal(xs, f32s([6.0, 2.5, 7.0]))
    axpy(var xs, 2.0, [1.0, 2.0, 3.0])
    try expect_equal(xs, f32s([8.0, 6.5, 13.0]))

    let _ = try expect_fault(lambda (): add_to(var xs, [1.0]))

test "softmax, silu and rms_norm":
    var xs: List[Float32] = [1.0, 2.0, 3.0, 99.0]
    softmax(var xs, 3)
    try expect_close((xs[0] + xs[1] + xs[2]).to_float(), 1.0, 0.000001)
    try expect_close(xs[2].to_float(), 0.66524096, 0.000001)
    try expect_equal(xs[3].to_float(), 99.0)

    var ys: List[Float32] = [0.0, 1.0]
    silu(var ys)
    try expect_equal(ys[0].to_float(), 0.0)
    try expect_close(ys[1].to_float(), 0.7310586, 0.000001)

    var out = List[Float32]()
    rms_norm(var out, [3.0, 4.0], [1.0, 2.0], 0.0)
    try expect_close(out[0].to_float(), 3.0 / 3.5355339, 0.000001)
    try expect_close(out[1].to_float(), 8.0 / 3.5355339, 0.000001)

test "matvec multiplies by each row":
    let rows = 9
    let cols = 37
    let data = ramp(rows * cols, 3)
    let x = ramp(cols, 7)
    let m = Matrix(rows: rows, cols: cols, data: data.clone())
    var out = List[Float32]()
    m.matvec(x, var out)
    try expect_equal(out.length(), rows)
    for r in 0..rows:
        try expect_equal(out[r], scalar_dot(data, r * cols, x, 0, cols))
    m.matvec_rows(x, 4, var out)
    try expect_equal(out.length(), 4)

    let _ = try expect_fault(lambda (): m.matvec(ramp(36, 1), var out))

test "a large matvec split across threads matches a scalar loop":
    # 1501 x 1001 is past the size where matvec uses the compute pool; odd sizes leave a short
    # last chunk and a scalar tail in every row.
    let rows = 1501
    let cols = 1001
    let data = ramp(rows * cols, 5)
    let x = ramp(cols, 3)
    let m = Matrix(rows: rows, cols: cols, data: data.clone())
    var out = List[Float32]()

    for _round in 0..3:
        m.matvec(x, var out)
        try expect_equal(out.length(), rows)
        for r in 0..rows:
            try expect_equal(out[r], scalar_dot(data, r * cols, x, 0, cols))

    m.matvec_rows(x, 1100, var out)
    try expect_equal(out.length(), 1100)
    try expect_equal(out[1099], scalar_dot(data, 1099 * cols, x, 0, cols))

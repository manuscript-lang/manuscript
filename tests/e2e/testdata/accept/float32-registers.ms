from "@std/testing.ms" import expect_equal

type Pair:
    left: Float32
    right: Float32

def sum_pair(p: Pair) -> Float32:
    return p.left + p.right

def dot(a: List[Float32], b: List[Float32]) -> Float32:
    var acc: Float32 = 0.0
    var i = 0
    while i < a.length():
        acc = acc + a[i] * b[i]
        i += 1
    return acc

test "arithmetic rounds to binary32 at every step":
    let a: Float32 = 16777216.0
    let b: Float32 = 1.0
    try expect_equal((a + b).to_float(), 16777216.0)
    let tenth: Float32 = 0.1
    try expect_equal((tenth + tenth + tenth).to_float(), 0.30000001192092896)
    try expect_equal((tenth * tenth).to_float(), 0.010000000707805157)

test "Float32 crosses calls, fields, closures and lists":
    try expect_equal(sum_pair(Pair(0.25, 0.5)).to_float(), 0.75)
    let scale: Float32 = 1.5
    let apply: Callable[[Float32], Float32] = lambda x: x * scale
    try expect_equal(apply(4.0).to_float(), 6.0)
    let xs: List[Float32] = [1.0, 2.0, 3.0]
    let ys: List[Float32] = [0.5, 0.25, 0.125]
    try expect_equal(dot(xs, ys).to_float(), 1.375)

test "Float32 compares and formats":
    let a: Float32 = 0.1
    let b: Float32 = 0.2
    try expect_equal(a < b, True)
    try expect_equal(a == b, False)
    try expect_equal(f"{a}", "0.1")
    let widened = a.to_float()
    try expect_equal(widened > 0.1, True)

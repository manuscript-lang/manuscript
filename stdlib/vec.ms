# Fast numeric kernels over `List[Float32]`: dot products, sums, element-wise updates and
# matrix-vector products, the building blocks of neural-network inference.
#
# The reductions (`dot`, `dot_at`, `fast_sum`, `Matrix.matvec`, and the maximum inside `softmax`)
# use the CPU's vector instructions. Each binary carries a baseline copy and, on x86-64, an AVX2
# and FMA copy of these kernels, and runs the best one the machine supports. A `matvec` of more
# than about 250,000 multiply-adds also splits its rows across every core. Nothing needs to be
# configured.
#
# They add in a fixed order of their own instead of left to right: eight lanes, four
# accumulators, then a pairwise sum. Results therefore differ in the last bits from a plain loop,
# and the AVX2 copy fuses each multiply-add, so they can also differ between CPUs. The same binary
# on the same CPU always gives the same result, whatever the number of cores. Compare with a
# tolerance (`expect_close`).
#
# ```manuscript
# from "@std/vec.ms" import Matrix, dot
#
# let w = Matrix(rows: 2, cols: 3, data: [1.0, 2.0, 3.0, 4.0, 5.0, 6.0])
# var out = List[Float32]()
# w.matvec([1.0, 1.0, 1.0], var out)   # out is [6.0, 15.0]
# let d = dot([1.0, 2.0], [3.0, 4.0])  # 11.0
# ```
from "@std/core.ms" import panic
from "@std/lanes.ms" import Lanes
from "@std/math.ms" import exp, sqrt

extern def msrt_lanes_splat(value: Float32) -> Lanes

extern def msrt_lanes_load(values: List[Float32], at: Int) -> Lanes

# Like `msrt_lanes_load` without the range check: only for indices the caller has checked.
extern def msrt_lanes_load_unchecked(values: List[Float32], at: Int) -> Lanes

# `left + right` without the overflow check, for indices already known to be in range.
extern def msrt_bits_wrapping_add(left: Int, right: Int) -> Int

extern def msrt_lanes_add(left: Lanes, right: Lanes) -> Lanes

extern def msrt_lanes_fma(left: Lanes, right: Lanes, add: Lanes) -> Lanes

extern def msrt_lanes_max(left: Lanes, right: Lanes) -> Lanes

extern def msrt_lanes_sum(values: Lanes) -> Float32

extern def msrt_lanes_hmax(values: Lanes) -> Float32

# Runs `body(start, end)` over `0 .. count` in chunks of at least `grain` rows on the runtime's
# compute pool, the calling thread included, and returns when all have finished. `body` runs on
# other threads, so it may only read its captures and write disjoint elements of a `var` capture:
# no allocation, recursion or faults. Small ranges run on the calling thread.
extern def msrt_parallel_rows(
    count: Int,
    grain: Int,
    body: Callable[[Int, Int], Unit]
) -> Unit

# The sum of `a[a_start + i] * b[b_start + i]` for each `i` below `count`. Faults when either range
# leaves its list.
export def dot_at(
    a: List[Float32],
    a_start: Int,
    b: List[Float32],
    b_start: Int,
    count: Int
) -> Float32:
    check_range("dot_at", a.length(), a_start, count)
    check_range("dot_at", b.length(), b_start, count)

    # Both ranges are checked, so the loads below cannot leave their lists.
    var acc0 = msrt_lanes_splat(0.0)
    var acc1 = msrt_lanes_splat(0.0)
    var acc2 = msrt_lanes_splat(0.0)
    var acc3 = msrt_lanes_splat(0.0)
    var i = 0
    var x = a_start
    var y = b_start

    while i + 32 <= count:
        acc0 = msrt_lanes_fma(
            msrt_lanes_load_unchecked(a, x), msrt_lanes_load_unchecked(b, y), acc0
        )
        acc1 = msrt_lanes_fma(
            msrt_lanes_load_unchecked(a, msrt_bits_wrapping_add(x, 8)),
            msrt_lanes_load_unchecked(b, msrt_bits_wrapping_add(y, 8)), acc1
        )
        acc2 = msrt_lanes_fma(
            msrt_lanes_load_unchecked(a, msrt_bits_wrapping_add(x, 16)),
            msrt_lanes_load_unchecked(b, msrt_bits_wrapping_add(y, 16)), acc2
        )
        acc3 = msrt_lanes_fma(
            msrt_lanes_load_unchecked(a, msrt_bits_wrapping_add(x, 24)),
            msrt_lanes_load_unchecked(b, msrt_bits_wrapping_add(y, 24)), acc3
        )
        x = msrt_bits_wrapping_add(x, 32)
        y = msrt_bits_wrapping_add(y, 32)
        i = msrt_bits_wrapping_add(i, 32)

    while i + 8 <= count:
        acc0 = msrt_lanes_fma(
            msrt_lanes_load_unchecked(a, x), msrt_lanes_load_unchecked(b, y), acc0
        )
        x = msrt_bits_wrapping_add(x, 8)
        y = msrt_bits_wrapping_add(y, 8)
        i = msrt_bits_wrapping_add(i, 8)

    var total = msrt_lanes_sum(
        msrt_lanes_add(msrt_lanes_add(acc0, acc1), msrt_lanes_add(acc2, acc3))
    )

    while i < count:
        total += a[a_start + i] * b[b_start + i]
        i += 1

    return total

# Faults unless `start .. start + count` lies within a list of `length` elements.
def check_range(name: String, length: Int, start: Int, count: Int) -> Unit:
    if count < 0 or start < 0 or start > length - count:
        panic(f"{name}: range {start} + {count} is outside a list of {length}")

# The sum of `a[i] * b[i]` over both lists. Faults when their lengths differ.
export def dot(a: List[Float32], b: List[Float32]) -> Float32:
    if a.length() != b.length():
        panic(f"dot: lengths differ ({a.length()} and {b.length()})")
    return dot_at(a, 0, b, 0, a.length())

# The sum of the elements in the vector order described above; 0.0 for an empty list.
# `values.sum()` adds left to right instead.
export def fast_sum(values: List[Float32]) -> Float32:
    let n = values.length()
    var acc0 = msrt_lanes_splat(0.0)
    var acc1 = msrt_lanes_splat(0.0)
    var i = 0

    while i + 16 <= n:
        acc0 = msrt_lanes_add(acc0, msrt_lanes_load_unchecked(values, i))
        acc1 = msrt_lanes_add(acc1, msrt_lanes_load_unchecked(values, i + 8))
        i += 16

    var total = msrt_lanes_sum(msrt_lanes_add(acc0, acc1))

    while i < n:
        total += values[i]
        i += 1

    return total

# The largest of the first `count` elements (at least one). A NaN element makes the result NaN.
def largest(values: List[Float32], count: Int) -> Float32:
    var i = 0
    var best = element(values, 0)

    if count >= 8:
        var acc = msrt_lanes_load_unchecked(values, 0)
        i = 8

        while i + 8 <= count:
            acc = msrt_lanes_max(acc, msrt_lanes_load_unchecked(values, i))
            i += 8

        best = msrt_lanes_hmax(acc)

    while i < count:
        let x = values[i]
        if x > best or x != x:
            best = x
        i += 1

    return best

# The index of the first largest element, or none for an empty list.
export def argmax(values: List[Float32]) -> Optional[Int]:
    if values.length() == 0:
        return none

    var best = 0
    var i = 1

    while i < values.length():
        if values[i] > values[best]:
            best = i
        i += 1

    return some(best)

# Multiplies every element by `factor`.
export def scale(var values: List[Float32], factor: Float32) -> Unit:
    var i = 0

    while i < values.length():
        values[i] = values[i] * factor
        i += 1

# Adds `values[i]` to `into[i]`. Faults when the lengths differ.
export def add_to(var into: List[Float32], values: List[Float32]) -> Unit:
    if into.length() != values.length():
        panic(f"add_to: lengths differ ({into.length()} and {values.length()})")

    var i = 0

    while i < into.length():
        into[i] = into[i] + values[i]
        i += 1

# Multiplies `into[i]` by `values[i]`. Faults when the lengths differ.
export def multiply_by(var into: List[Float32], values: List[Float32]) -> Unit:
    if into.length() != values.length():
        panic(f"multiply_by: lengths differ ({into.length()} and {values.length()})")

    var i = 0

    while i < into.length():
        into[i] = into[i] * values[i]
        i += 1

# Adds `factor * values[i]` to `into[i]`. Faults when the lengths differ.
export def axpy(var into: List[Float32], factor: Float32, values: List[Float32]) -> Unit:
    if into.length() != values.length():
        panic(f"axpy: lengths differ ({into.length()} and {values.length()})")

    var i = 0

    while i < into.length():
        into[i] = into[i] + factor * values[i]
        i += 1

# Replaces the first `count` elements with their softmax: each becomes `exp(x - max)` divided by
# the sum of those exponentials. Elements from `count` on are unchanged.
export def softmax(var values: List[Float32], count: Int) -> Unit:
    if count <= 0:
        return

    if count > values.length():
        panic(f"softmax: {count} elements requested, list has {values.length()}")

    let top = largest(values, count)
    var total: Float32 = 0.0
    var i = 0

    while i < count:
        let e = exp((values[i] - top).to_float()).to_float32()
        values[i] = e
        total += e
        i += 1

    i = 0

    while i < count:
        values[i] = values[i] / total
        i += 1

# Replaces every element `x` with `x / (1 + exp(-x))` (SiLU).
export def silu(var values: List[Float32]) -> Unit:
    var i = 0

    while i < values.length():
        let x = values[i].to_float()
        values[i] = (x / (1.0 + exp(-x))).to_float32()
        i += 1

# Writes the RMS-normalized `values`, scaled element-wise by `weight`, into `out`, which is resized
# to match: `out[i] = weight[i] * values[i] / sqrt(mean(values^2) + epsilon)`.
export def rms_norm(
    var out: List[Float32], values: List[Float32], weight: List[Float32],
    epsilon: Float32
) -> Unit:
    let n = values.length()
    if weight.length() != n:
        panic(f"rms_norm: lengths differ ({n} and {weight.length()})")

    let mean = dot_at(values, 0, values, 0, n).to_float() / n.to_float()
    let inv = (1.0 / sqrt(mean + epsilon.to_float())).to_float32()
    resize(var out, n)

    var i = 0

    while i < n:
        out[i] = weight[i] * (values[i] * inv)
        i += 1

# A copy of `values[i]`, so a `var` can start from it without borrowing the list.
def element(values: List[Float32], i: Int) -> Float32:
    return values[i]

# Makes `values` exactly `n` elements long, appending zeros or dropping from the end.
def resize(var values: List[Float32], n: Int) -> Unit:
    while values.length() < n:
        values.append(0.0)
    while values.length() > n:
        let _dropped = values.pop()

# A row-major matrix of `Float32`: element `(r, c)` is `data[r * cols + c]`.
export type Matrix:
    # Number of rows; `matvec` writes one output element per row.
    rows: Int
    # Number of columns; vectors passed to `matvec` must have exactly this many elements.
    cols: Int
    # The elements, row by row; its length must be `rows * cols`.
    data: List[Float32]

impl Matrix:
    # Writes `self * x` into `out`, which is resized to `rows`: `out[r]` is the dot product of row
    # `r` with `x`. Faults when `x` does not have `cols` elements or `data` is too short.
    def matvec(x: List[Float32], var out: List[Float32]) -> Unit:
        self.matvec_rows(x, self.rows, var out)

    # Like `matvec`, but for the first `count` rows only; `out` is resized to `count`. Useful
    # when only part of a preallocated matrix is filled, such as an attention cache.
    def matvec_rows(x: List[Float32], count: Int, var out: List[Float32]) -> Unit:
        if x.length() != self.cols:
            panic(
                f"matvec: vector has {x.length()} elements, matrix has {self.cols} columns"
            )
        if count < 0 or count > self.rows:
            panic(f"matvec: {count} rows requested, matrix has {self.rows}")
        resize(var out, count)

        let cols = self.cols
        check_range("matvec", self.data.length(), 0, count * cols)

        # Rows are independent, so the result does not depend on how the pool splits them. Each
        # chunk does at least `PARALLEL_WORK` multiply-adds.
        msrt_parallel_rows(
            count,
            PARALLEL_WORK / max_int(cols, 1),
            lambda (start: Int, end: Int):
                var r = start

                while r < end:
                    out[r] = dot_at(self.data, r * cols, x, 0, cols)
                    r += 1
        )

# The fewest multiply-adds `matvec` hands to one thread: waking the pool costs a few
# microseconds, a small part of what one core needs for this many.
let PARALLEL_WORK = 262144

def max_int(a: Int, b: Int) -> Int:
    return a if a > b else b

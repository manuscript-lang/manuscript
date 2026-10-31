# Python's `random.Random` (Mersenne Twister) for integer seeds, so the generators reproduce the cases
# CPython's `random` module produced. Covers `randint`, `randrange`, `choice`, `random` and `sample`.
import panic from "@std/core.ms"
import bit_and, bit_xor, shift_left, shift_right from "@std/math.ms"

let N = 624
let MASK = 0xFFFFFFFF

export type Random:
    state: List[Int]
    index: Int

fn u32(value: Int) Int: bit_and(value, MASK)

fn init_genrand(seed: Int) List[Int]:
    var mt = List[Int](reserve: N)
    mt.append(u32(seed))

    for i in 1..N:
        let prev = mt[i - 1]
        mt.append(u32(1812433253 * bit_xor(prev, shift_right(prev, 30)) + i))

    return mt

# Seeds like `random.Random(seed)` for a non-negative `seed` below 2**32.
export fn seeded(seed: Int) Random:
    var mt = init_genrand(19650218)
    var i = 1
    var j = 0
    var k = N

    while k > 0:
        let prev = mt[i - 1]
        mt[i] = u32(
            bit_xor(
                mt[i], bit_xor(prev, shift_right(prev, 30)) * 1664525
            ) + seed + j
        )
        i += 1
        j += 1

        if i >= N:
            mt[0] = mt[N - 1]
            i = 1

        if j >= 1: j = 0
        k -= 1

    k = N - 1

    while k > 0:
        let prev = mt[i - 1]
        mt[i] = u32(
            bit_xor(
                mt[i], bit_xor(prev, shift_right(prev, 30)) * 1566083941
            ) - i
        )
        i += 1

        if i >= N:
            mt[0] = mt[N - 1]
            i = 1

        k -= 1

    mt[0] = 0x80000000
    return Random(mt, N)

fn twist(var mt: List[Int]) Unit:
    for kk in 0..N:
        let y = bit_and(mt[kk], 0x80000000) + bit_and(mt[(kk + 1) % N], 0x7FFFFFFF)
        var next = bit_xor(mt[(kk + 397) % N], shift_right(y, 1))
        if bit_and(y, 1) == 1: next = bit_xor(next, 0x9908B0DF)
        mt[kk] = next

impl Random:
    var fn next_u32() Int:
        if self.index >= N:
            twist(var self.state)
            self.index = 0

        let word = self.state[self.index]
        self.index += 1

        let y1 = bit_xor(word, shift_right(word, 11))
        let y2 = bit_xor(y1, bit_and(shift_left(y1, 7), 0x9D2C5680))
        let y3 = bit_xor(y2, bit_and(shift_left(y2, 15), 0xEFC60000))
        return bit_xor(y3, shift_right(y3, 18))

    # A uniform integer in `0..n` by rejection, as CPython's `_randbelow`.
    var fn below(n: Int) Int:
        if n <= 0: return 0

        var bits = 0
        var m = n

        while m > 0:
            bits += 1
            m = shift_right(m, 1)

        var r = shift_right(self.next_u32(), 32 - bits)
        while r >= n: r = shift_right(self.next_u32(), 32 - bits)
        return r

    # A uniform integer in `low..=high`.
    var fn randint(low: Int, high: Int) Int: low + self.below(high - low + 1)

    # A uniform integer in `low..high`.
    var fn randrange(low: Int, high: Int) Int: low + self.below(high - low)

    # A uniform float in `0.0..1.0` from 53 random bits.
    var fn random() Float:
        let a = shift_right(self.next_u32(), 5)
        let b = shift_right(self.next_u32(), 6)
        return (a.to_float() * 67108864.0 + b.to_float()) / 9007199254740992.0

    # A uniformly chosen item, as `random.choice`. The index is bound before the element is cloned because
    # `items[f()].clone()` evaluates `f()` twice (https://github.com/manuscript-lang/manuscript/issues/2161).
    var fn choice(items: List[String]) String:
        let at = self.below(items.length())
        return items[at].clone()

    # `k` distinct items in random order, as `random.sample` picks them from a population of at most 21 items
    # (CPython's pool method; larger populations use a different algorithm that is not implemented here).
    var fn sample(items: List[String], k: Int) List[String]:
        let n = items.length()
        if n > 21: panic("sample: only the pool method is implemented")

        var pool = items.clone()
        var out = List[String]()

        for i in 0..k:
            let j = self.below(n - i)
            out.append(pool[j].clone())
            pool[j] = pool[n - i - 1].clone()

        return out

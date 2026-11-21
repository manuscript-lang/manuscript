#!/usr/bin/env python3
"""Writes src/runtime/tests/oracle/bigint.tsv: BigInt operations with answers from Python's integers, which are exact.
Usage: python3 -I src/runtime/tests/oracle/bigint_gen.py > src/runtime/tests/oracle/bigint.tsv   (deterministic).

One case per line, tab separated: `op a b c expected`; unused fields are `-`; `expected` is a decimal integer,
`ERR<status>` for a call that fails with that STATUS_* code, or (for to_float) the float's hex form."""
import random
import sys

sys.set_int_max_str_digits(0)
rng = random.Random(20261120)
MAX_BITS = 1 << 24
I64_MIN, I64_MAX = -(1 << 63), (1 << 63) - 1


def edge_values():
    out = {0, 1, -1, 2, -2, 10, -10, I64_MIN, I64_MAX, I64_MAX + 1, I64_MIN - 1, (1 << 64) - 1, 1 << 64}
    for k in (31, 32, 53, 63, 64, 65, 127, 128, 129, 191, 192, 1023, 1024, 2047, 2048):
        for d in (-1, 0, 1):
            out.add((1 << k) + d)
            out.add(-((1 << k) + d))
    return sorted(out)


def rand_value(bits):
    value = rng.getrandbits(bits) if bits else 0
    return -value if rng.random() < 0.4 else value


EDGES = edge_values()
SIZES = [1, 8, 31, 64, 65, 100, 128, 200, 500, 1000, 2100]


def operand():
    r = rng.random()
    if r < 0.25:
        return rng.choice(EDGES)
    return rand_value(rng.choice(SIZES))


def fmt(v):
    return str(v)


def trunc_div(a, b):
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def trunc_rem(a, b):
    return a - b * trunc_div(a, b)


def to_float(v):
    try:
        return float(v)
    except OverflowError:
        return float("inf") if v > 0 else float("-inf")


def isqrt(v):
    import math
    return math.isqrt(v)


lines = []


PER_OP = 50  # cases kept per operation: enough to cover each rule, small enough to review
kept = {}


def emit(op, a="-", b="-", c="-", expected="-"):
    kept[op] = kept.get(op, 0) + 1
    if kept[op] <= PER_OP or expected.startswith("ERR"):
        lines.append("\t".join([op, a, b, c, expected]))


def binary(op, fn, count=110):
    for _ in range(count):
        a, b = operand(), operand()
        emit(op, fmt(a), fmt(b), expected=fmt(fn(a, b)))


binary("add", lambda a, b: a + b)
binary("subtract", lambda a, b: a - b)
binary("multiply", lambda a, b: a * b)
for _ in range(24):  # large products: Karatsuba, balanced and lopsided
    a, b = rand_value(rng.choice([4200, 8200])), rand_value(rng.choice([64, 2200, 4200, 8200]))
    emit("multiply", fmt(a), fmt(b), expected=fmt(a * b))
binary("and", lambda a, b: a & b)
binary("or", lambda a, b: a | b)
binary("xor", lambda a, b: a ^ b)
binary("gcd", lambda a, b: __import__("math").gcd(a, b))
binary("lcm", lambda a, b: abs(a * b) // __import__("math").gcd(a, b) if a and b else 0)
binary("compare", lambda a, b: (a > b) - (a < b))
for op, fn in (("divide", trunc_div), ("remainder", trunc_rem)):
    for _ in range(180):
        a, b = operand(), operand()
        if b == 0:
            emit(op, fmt(a), "0", expected="ERR1")
        else:
            emit(op, fmt(a), fmt(b), expected=fmt(fn(a, b)))
for _ in range(30):  # multi-limb division
    a = rand_value(rng.choice([2000, 5000]))
    b = rand_value(rng.choice([65, 130, 700, 2000]))
    b = b or 3
    emit("divide", fmt(a), fmt(b), expected=fmt(trunc_div(a, b)))
    emit("remainder", fmt(a), fmt(b), expected=fmt(trunc_rem(a, b)))
for k in (64, 128, 512):
    for d in (0, 1, -1):  # dividends and divisors at limb boundaries
        a, b = (1 << (3 * k)) + d, (1 << k) - 1
        emit("divide", fmt(a), fmt(b), expected=fmt(trunc_div(a, b)))
        emit("remainder", fmt(-a), fmt(b), expected=fmt(trunc_rem(-a, b)))
for v in [operand() for _ in range(80)]:
    emit("negate", fmt(v), expected=fmt(-v))
    emit("abs", fmt(v), expected=fmt(abs(v)))
    emit("not", fmt(v), expected=fmt(~v))
    emit("sign", fmt(v), expected=fmt((v > 0) - (v < 0)))
    emit("to_float", fmt(v), expected=to_float(v).hex())
    emit("to_int", fmt(v), expected=fmt(v) if I64_MIN <= v <= I64_MAX else "ERR0")
for _ in range(120):
    v = operand()
    count = rng.choice([0, 1, 7, 63, 64, 65, 130, 1000])
    emit("shift_left", fmt(v), str(count), expected=fmt(v << count))
    emit("shift_right", fmt(v), str(count), expected=fmt(v >> count))
for v in (1, -1, 5, -5, 1 << 100, -(1 << 100)):
    emit("shift_right", fmt(v), "100000", expected=fmt(v >> 100000))
    emit("shift_left", fmt(v), str(MAX_BITS + 1), expected="ERR3")
emit("shift_left", "1", "-1", expected="ERR1")
emit("shift_right", "1", "-1", expected="ERR1")
emit("shift_left", "0", str(MAX_BITS + 5), expected="0")
for _ in range(60):
    v = abs(operand())
    emit("sqrt", fmt(v), expected=fmt(isqrt(v)))
for k in (64, 128, 1024):
    for d in (-1, 0, 1):
        v = (1 << (2 * k)) + d * (1 << k)
        emit("sqrt", fmt(v), expected=fmt(isqrt(v)))
emit("sqrt", "-1", expected="ERR1")
for _ in range(60):
    base = operand()
    exp = rng.choice([0, 1, 2, 3, 7, 31, 100, 257])
    if base == 0 or exp == 0 or abs(base).bit_length() * exp < 6000:
        emit("pow", fmt(base), str(exp), expected=fmt(base ** exp))
emit("pow", "2", "-1", expected="ERR1")
emit("pow", "2", str(MAX_BITS), expected="ERR3")
emit("pow", "1", "9223372036854775807", expected="1")
emit("pow", "-1", "9223372036854775807", expected="-1")
emit("pow", "0", "9223372036854775807", expected="0")
emit("pow", "2", str(MAX_BITS - 1), expected="-")  # checked by length only
for _ in range(80):
    m = abs(operand()) + 1
    a, e = operand(), abs(rng.choice(EDGES)) % 5000 + rng.choice([0, 0, 1])
    emit("pow_mod", fmt(a), fmt(e), fmt(m), expected=fmt(pow(a, e, m)))
emit("pow_mod", "2", "-1", "5", expected="ERR1")
emit("pow_mod", "2", "3", "0", expected="ERR1")
emit("pow_mod", "2", "3", "-5", expected="ERR1")
for _ in range(120):
    m = abs(operand()) + 1
    a = operand()
    try:
        r = pow(a, -1, m) if m > 1 else 0
    except ValueError:
        r = None
    emit("inverse_mod", fmt(a), fmt(m), expected="ERR0" if r is None else fmt(r))
emit("inverse_mod", "3", "0", expected="ERR0")
emit("inverse_mod", "3", "-7", expected="ERR0")
for radix in (2, 3, 7, 8, 10, 16, 32, 36):
    for _ in range(25):
        v = operand()
        digits = "0123456789abcdefghijklmnopqrstuvwxyz"
        n, out = abs(v), ""
        while n:
            n, r = divmod(n, radix)
            out = digits[r] + out
        text = ("-" if v < 0 else "") + (out or "0")
        emit("format", fmt(v), str(radix), expected=text)
        emit("parse", text, str(radix), expected=fmt(v))
        emit("parse", text.upper(), str(radix), expected=fmt(v))
for text, radix, status in (("", 10, 4), ("-", 10, 4), ("+", 10, 4), ("1_0", 10, 4), (" 1", 10, 4), ("12", 2, 4),
                            ("z", 35, 4), ("1", 1, 1), ("1", 37, 1)):
    emit("parse", text or "-empty-", str(radix), expected=f"ERR{status}")
emit("parse_max", "12345", "10", "5", expected="12345")
emit("parse_max", "12345", "10", "4", expected="ERR3")
emit("parse_max", "-12345", "10", "5", expected="-12345")
emit("parse_max", "+-1", "10", "2", expected="ERR4")
emit("parse_max", "+-1", "10", "1", expected="ERR3")
emit("parse_max", "1", "10", "-1", expected="ERR1")
emit("parse_max", "0", "10", "0", expected="ERR3")
sys.stdout.write("\n".join(lines) + "\n")

#!/usr/bin/env python3
"""Writes src/runtime/tests/oracle/decimal.tsv: Decimal operations with answers from Python's decimal module (IEEE 754
decimal128 arithmetic: 34 digits, half-even, Emax 6144, Emin -6143) and exact integer arithmetic for rounding and
text. Usage: python3 -I src/runtime/tests/oracle/decimal_gen.py > src/runtime/tests/oracle/decimal.tsv   (deterministic).

One case per line, tab separated: `op a b c expected`. A Decimal is written `coefficient,exponent` (normalised: no
trailing zeros in the coefficient, zero is `0,0`). `expected` is a Decimal, an integer, text, `OVERFLOW` for the
operator fault, `DIVZERO`, or `ERR<status>`."""
import random
import re
import sys
sys.set_int_max_str_digits(0)
from decimal import ROUND_HALF_EVEN, Context, Decimal, Overflow, DivisionByZero
from fractions import Fraction

rng = random.Random(20261120)
DIGITS, MIN_Q, MAX_E = 34, -6176, 6144
CTX = Context(prec=DIGITS, rounding=ROUND_HALF_EVEN, Emax=MAX_E, Emin=-6143, traps=[Overflow, DivisionByZero])
I64_MIN, I64_MAX = -(1 << 63), (1 << 63) - 1


def normal(coef, exp):
    if coef == 0:
        return (0, 0)
    while coef % 10 == 0:
        coef //= 10
        exp += 1
    return (coef, exp)


def valid(coef, exp):
    coef, exp = normal(coef, exp)
    return coef == 0 or (len(str(abs(coef))) <= DIGITS and exp >= MIN_Q and exp + len(str(abs(coef))) - 1 <= MAX_E)


def dec(pair):
    return Decimal(pair[0]).scaleb(pair[1], context=Context(prec=100000, Emax=999999, Emin=-999999))


def pair_of(d):
    sign, digits, exp = d.as_tuple()
    coef = int("".join(map(str, digits)) or "0")
    return normal(-coef if sign else coef, exp)


def text(pair):
    return f"{pair[0]},{pair[1]}"


def operand():
    r = rng.random()
    if r < 0.2:
        return rng.choice(EDGES)
    digits = rng.choice([1, 2, 3, 5, 10, 17, 25, 33, 34])
    coef = rng.randrange(10 ** (digits - 1), 10 ** digits)
    coef = -coef if rng.random() < 0.4 else coef
    low = max(MIN_Q, -rng.choice([5, 40, 6176]))
    high = min(MAX_E - digits + 1, rng.choice([5, 40, 6111]))
    exp = rng.randint(low, max(low, high))
    pair = normal(coef, exp)
    return pair if valid(*pair) else (1, 0)


EDGES = [(0, 0), (1, 0), (-1, 0), (1, -1), (5, -1), (10 ** 34 - 1, 0), (-(10 ** 34 - 1), 0), (1, MAX_E), (1, MIN_Q),
         (10 ** 34 - 1, MAX_E - 33), (10 ** 34 - 1, MIN_Q), (-(10 ** 34 - 1), MAX_E - 33), (1, 6111), (9, -1)]
lines = []


PER_OP = 50  # cases kept per operation: enough to cover each rule, small enough to review
kept = {}


def emit(op, a="-", b="-", c="-", expected="-"):
    kept[op] = kept.get(op, 0) + 1
    if kept[op] <= PER_OP or expected.startswith("ERR"):
        lines.append("\t".join([op, a, b, c, expected]))


def arithmetic(op, fn, count):
    for _ in range(count):
        a, b = operand(), operand()
        if rng.random() < 0.3:  # operands whose exponents are within a few places of each other
            b = normal(b[0], a[1] + rng.randint(-40, 40))
            if not valid(*b):
                b = a
        try:
            result = text(pair_of(fn(dec(a), dec(b))))
        except Overflow:
            result = "OVERFLOW"
        except DivisionByZero:
            result = "DIVZERO"
        emit(op, text(a), text(b), expected=result)


arithmetic("add", lambda a, b: CTX.add(a, b), 260)
arithmetic("subtract", lambda a, b: CTX.subtract(a, b), 260)
arithmetic("multiply", lambda a, b: CTX.multiply(a, b), 260)
arithmetic("divide", lambda a, b: CTX.divide(a, b) if b != 0 else (_ for _ in ()).throw(DivisionByZero()), 260)
for _ in range(100):
    a, b = operand(), operand()
    emit("compare", text(a), text(b), expected=str((dec(a) > dec(b)) - (dec(a) < dec(b))))
for _ in range(60):
    a = operand()
    emit("negate", text(a), expected=text((-a[0], a[1]) if a[0] else (0, 0)))
    value = dec(a)
    try:
        emit("to_float", text(a), expected=float(value).hex())
    except OverflowError:
        emit("to_float", text(a), expected=("inf" if value > 0 else "-inf"))
    truncated = int(value)
    emit("truncate", text(a), expected=str(truncated) if I64_MIN <= truncated <= I64_MAX else "NONE")
for n in [0, 1, -1, 10, 100, 12300, I64_MAX, I64_MIN, I64_MIN + 1, 10 ** 18, -(10 ** 18)] + [
        rng.randint(I64_MIN, I64_MAX) for _ in range(40)]:
    emit("from_int", str(n), expected=text(normal(n, 0)))
    if n >= 0 or n == I64_MIN:  # from_uint takes the int64 bit pattern of an unsigned value
        pass
for n in [0, 1, 10, (1 << 64) - 1, (1 << 63), 10 ** 19, rng.getrandbits(64), rng.getrandbits(64)]:
    emit("from_uint", str(n), expected=text(normal(n, 0)))


def render(pair):
    coef, exp = pair
    if coef == 0:
        return "0"
    digits = str(abs(coef)).rstrip("0")
    exponent = exp + len(str(abs(coef))) - 1
    sign = "-" if coef < 0 else ""
    if -6 <= exponent <= 20:
        point = exponent + 1
        if point <= 0:
            return f"{sign}0.{'0' * -point}{digits}"
        if point >= len(digits):
            return f"{sign}{digits}{'0' * (point - len(digits))}"
        return f"{sign}{digits[:point]}.{digits[point:]}"
    body = digits[0] + ("." + digits[1:] if len(digits) > 1 else "")
    return f"{sign}{body}e{'+' if exponent >= 0 else ''}{exponent}"


for _ in range(150):
    a = operand()
    emit("to_string", text(a), expected=render(a))
for exp in (-8, -7, -6, -1, 0, 19, 20, 21, 22):
    for coef in (1, 12, -12345, 10 ** 33 + 7):
        emit("to_string", text(normal(coef, exp)), expected=render(normal(coef, exp)))


def rounding(value, mode):
    """The Fraction `value` as an integer under RoundingMode `mode`."""
    floor = value.numerator // value.denominator
    rest = value - floor
    if rest == 0:
        return floor
    if mode == 3:
        return floor
    if mode == 4:
        return floor + 1
    if mode == 2:
        return floor if value > 0 else floor + 1
    half = Fraction(1, 2)
    if rest != half:
        return floor + 1 if rest > half else floor
    if mode == 1:
        return floor + 1 if value > 0 else floor
    return floor if floor % 2 == 0 else floor + 1


def scaled(pair, places, mode):
    return rounding(Fraction(pair[0]) * Fraction(10) ** (pair[1] + places), mode)


for _ in range(300):
    a = operand()
    places = rng.choice([-6144, -40, -3, -1, 0, 1, 2, 5, 33, 34, 35, 40, 6176, a[1] * -1, -a[1] + 1, -a[1] - 1])
    places = max(-6144, min(6176, places))
    mode = rng.choice([0, 1, 2, 3, 4])
    has = rng.choice([1, 1, 1, 0])
    effective = mode if has else 0
    if a[0] == 0 or a[1] + places >= 0:
        result = text(a)
    else:
        coef, exp = normal(scaled(a, places, effective), -places)
        digits = len(str(abs(coef)))
        result = "ERR2" if coef != 0 and (digits > DIGITS or exp < MIN_Q or exp + digits - 1 > MAX_E) else text((coef, exp))
    emit("round", text(a), f"{places},{has},{mode}", expected=result)
emit("round", "1,0", "6177,0,0", expected="ERR1")
emit("round", "1,0", "-6145,0,0", expected="ERR1")
emit("round", "1,0", "0,1,5", expected="ERR1")
for _ in range(300):
    a = operand()
    digits = rng.choice([0, 1, 2, 3, 10, 34, 40, 100, 6176, max(0, -a[1]), max(0, -a[1] + 1)])
    digits = min(digits, 6176)
    mode, has = rng.choice([0, 1, 2, 3, 4]), rng.choice([1, 1, 0])
    n = scaled(a, digits, mode if has else 0)
    body = str(abs(n))
    if digits > 0:
        body = body.rjust(digits + 1, "0")
        body = body[:-digits] + "." + body[-digits:]
    emit("to_fixed", text(a), f"{digits},{has},{mode}", expected=("-" if n < 0 else "") + body)
emit("to_fixed", "1,0", "6177,0,0", expected="ERR1")
emit("to_fixed", "1,0", "-1,0,0", expected="ERR1")
emit("to_fixed", "1,0", "2,1,9", expected="ERR1")

LITERAL = re.compile(r"^[+-]?([0-9]+)(?:\.([0-9]+))?(?:[eE]([+-]?\d+))?d?$")


def parse_model(source):
    m = LITERAL.match(source)
    if not m:
        return "ERR1"
    whole, fraction, exponent_text = m.group(1), m.group(2) or "", m.group(3)
    digits = (whole + fraction).lstrip("0")
    if not digits:
        return "0,0"
    exponent = int(exponent_text) if exponent_text else 0
    if not (-(1 << 31) <= exponent < (1 << 31)):
        return "ERR1"
    coef = int(digits)
    pair = normal(-coef if source.lstrip().startswith("-") else coef, exponent - len(fraction))
    return text(pair) if valid(*pair) else "ERR1"


literals = ["0", "-0", "1", "+1", "-1", "1d", "1.5", "1.50d", "0.1d", "00012", "1e5", "1E5", "1e+5", "1e-5", "1.5e3d",
            "12345678901234567890123456789012345", "1234567890123456789012345678901234", "1e6144", "1e6145",
            "1e-6176", "1e-6177", "9.999999999999999999999999999999999e6144", "0e999999999999", "0.000e5",
            "1e2147483647", "1e2147483648", "1e-2147483648", "1e-2147483649", ".5", "5.", "1.2.3", "", "d", "-", "+",
            "--1", "+-1", "1e", "1e+", "1e-", "1_0", " 1", "1 ", "1dd", "1d5", "inf", "nan", "0x10", "1e5e5", "١",
            "100000000000000000000000000000000000000000", "0.00000000000000000000000000000000000001"]
for source in literals:
    emit("parse", source if source else "-empty-", expected=parse_model(source))
for _ in range(300):
    a = operand()
    source = f"{'-' if a[0] < 0 else rng.choice(['', '+'])}{abs(a[0])}e{a[1]}{rng.choice(['', 'd'])}"
    if rng.random() < 0.3:
        point = rng.randint(1, max(1, len(str(abs(a[0]))) - 1))
        digits = str(abs(a[0]))
        source = f"{'-' if a[0] < 0 else ''}{digits[:point]}.{digits[point:] or '0'}e{a[1] + len(digits) - point}"
    if rng.random() < 0.2 and source:
        at = rng.randrange(len(source))
        source = source[:at] + rng.choice("0123456789.-+eEd_ ") + source[at + rng.choice([0, 1]):]
    emit("parse", source, expected=parse_model(source))
sys.stdout.write("\n".join(lines) + "\n")

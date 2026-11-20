/* Number to text: decimal and radix integers, shortest round-trip floats, and the precision forms. They write into
 * a caller's buffer and allocate nothing, so one copy serves interpolation, to_string and the JSON encoder.
 * Ported from crates/ms-rt/src/num.rs and float_digits.rs; the output is byte-identical. */
#include "ms_rt/fmt.h"

#include "float_table.h"

typedef unsigned __int128 u128;

static size_t put(uint8_t *out, size_t n, const void *bytes, size_t len) {
    const uint8_t *src = bytes;
    for (size_t i = 0; i < len; i++) {
        out[n + i] = src[i];
    }
    return n + len;
}

static size_t put_str(uint8_t *out, size_t n, const char *s) {
    size_t len = 0;
    while (s[len]) {
        len++;
    }
    return put(out, n, s, len);
}

static size_t put_zeros(uint8_t *out, size_t n, size_t count) {
    for (size_t i = 0; i < count; i++) {
        out[n + i] = '0';
    }
    return n + count;
}

static const char pairs[201] =
    "0001020304050607080910111213141516171819"
    "2021222324252627282930313233343536373839"
    "4041424344454647484950515253545556575859"
    "6061626364656667686970717273747576777879"
    "8081828384858687888990919293949596979899";

size_t msrt_fmt_u64(uint64_t n, uint8_t *out) {
    uint8_t tmp[20];
    size_t i = sizeof tmp;
    while (n >= 100) {
        size_t r = (size_t)(n % 100) * 2;
        n /= 100;
        i -= 2;
        tmp[i] = (uint8_t)pairs[r];
        tmp[i + 1] = (uint8_t)pairs[r + 1];
    }
    if (n >= 10) {
        size_t r = (size_t)n * 2;
        i -= 2;
        tmp[i] = (uint8_t)pairs[r];
        tmp[i + 1] = (uint8_t)pairs[r + 1];
    } else {
        tmp[--i] = (uint8_t)('0' + n);
    }
    return put(out, 0, tmp + i, sizeof tmp - i);
}

size_t msrt_fmt_i64(int64_t v, uint8_t *out) {
    if (v >= 0) {
        return msrt_fmt_u64((uint64_t)v, out);
    }
    out[0] = '-';
    return 1 + msrt_fmt_u64(UINT64_C(0) - (uint64_t)v, out + 1);
}

size_t msrt_fmt_radix(uint64_t n, uint32_t radix, uint8_t negative, uint8_t *out) {
    uint8_t tmp[65];
    size_t i = sizeof tmp;
    do {
        uint32_t d = (uint32_t)(n % radix);
        tmp[--i] = (uint8_t)(d < 10 ? '0' + d : 'a' + d - 10);
        n /= radix;
    } while (n != 0);
    if (negative) {
        tmp[--i] = '-';
    }
    return put(out, 0, tmp + i, sizeof tmp - i);
}

/* ---- Shortest digits: Schubfach (Giulietti, 2020), as crates/ms-rt/src/float_digits.rs ---- */

#define MASK63 ((UINT64_C(1) << 63) - 1)

static int flog10_pow2(int e) { return (int)(((int64_t)e * INT64_C(677859288149821)) >> 51); }
static int flog10_three_quarters_pow2(int e) {
    return (int)(((int64_t)e * INT64_C(677859288149821) - INT64_C(281337023816645)) >> 51);
}
static int flog2_pow10(int e) { return (int)(((int64_t)e * INT64_C(935039633142891)) >> 48); }

/* g * cp / 2^127 rounded to odd, where g = g1 * 2^63 + g0. */
static uint64_t round_to_odd(uint64_t g1, uint64_t g0, uint64_t cp) {
    uint64_t x1 = (uint64_t)(((u128)g0 * cp) >> 64);
    u128 y = (u128)g1 * cp;
    uint64_t y1 = (uint64_t)(y >> 64), y0 = (uint64_t)y;
    uint64_t z = (y0 >> 1) + x1;
    uint64_t high = y1 + (z >> 63);
    return high | (((z & MASK63) + MASK63) >> 63);
}

/* The digits d and exponent e of the shortest decimal d * 10^e that rounds to the value c * 2^q, no trailing zero
 * stripped yet. qmin and cmin are the format's smallest exponent and its implicit bit. */
static uint64_t to_decimal(int q, uint64_t c, int qmin, uint64_t cmin, int *exp10) {
    uint64_t out = c & 1;
    uint64_t cb = c << 2;
    uint64_t cbr = cb + 2;
    uint64_t cbl;
    int k;
    if (c != cmin || q == qmin) {
        cbl = cb - 2;
        k = flog10_pow2(q);
    } else {
        cbl = cb - 1;
        k = flog10_three_quarters_pow2(q);
    }
    unsigned h = (unsigned)(q + flog2_pow10(-k) + 2);
    const uint64_t *g = ms_float_g[k - MS_FLOAT_K_MIN];
    uint64_t vb = round_to_odd(g[0], g[1], cb << h);
    uint64_t vbl = round_to_odd(g[0], g[1], cbl << h);
    uint64_t vbr = round_to_odd(g[0], g[1], cbr << h);
    *exp10 = k;

    uint64_t s = vb >> 2;
    if (s >= 10) {
        uint64_t sp10 = 10 * (s / 10);
        uint64_t tp10 = sp10 + 10;
        bool up_in = vbl + out <= sp10 << 2;
        bool wp_in = (tp10 << 2) + out <= vbr;
        if (up_in != wp_in) {
            return up_in ? sp10 : tp10;
        }
    }
    uint64_t t = s + 1;
    bool u_in = vbl + out <= s << 2;
    bool w_in = (t << 2) + out <= vbr;
    if (u_in != w_in) {
        return u_in ? s : t;
    }
    int64_t cmp = (int64_t)vb - (int64_t)((s + t) << 1);
    bool pick_s = cmp < 0 || (cmp == 0 && (s & 1) == 0);
    return pick_s ? s : t;
}

/* Shortest digits of a finite positive value into buf (at most 17); returns the count, *exp the decimal exponent of
 * the first digit. */
static size_t shortest(uint64_t bits, int mantissa_bits, int bias, uint8_t *buf, int *exp) {
    int biased = (int)(bits >> mantissa_bits) & 0x7ff; /* the sign bit is already clear */
    uint64_t fraction = bits & ((UINT64_C(1) << mantissa_bits) - 1);
    uint64_t cmin = UINT64_C(1) << mantissa_bits;
    int qmin = 1 - bias - mantissa_bits;
    int q;
    uint64_t c;
    if (biased != 0) {
        q = biased - bias - mantissa_bits;
        c = fraction | cmin;
    } else {
        q = qmin;
        c = fraction;
    }
    int e10;
    uint64_t d = to_decimal(q, c, qmin, cmin, &e10);
    while (d % 10 == 0) {
        d /= 10;
        e10++;
    }
    size_t n = msrt_fmt_u64(d, buf);
    *exp = e10 + (int)n - 1;
    return n;
}

/* Plain notation for exponents in -6..=20, else scientific; trailing zeros of the digits are dropped first. */
static size_t render_decimal(const uint8_t *digits, size_t n, int exponent, bool negative, uint8_t *out) {
    while (n > 1 && digits[n - 1] == '0') {
        n--;
    }
    size_t at = 0;
    if (negative) {
        out[at++] = '-';
    }
    if (exponent >= -6 && exponent <= 20) {
        int point = exponent + 1;
        if (point <= 0) {
            at = put_str(out, at, "0.");
            at = put_zeros(out, at, (size_t)-point);
            at = put(out, at, digits, n);
        } else if ((size_t)point >= n) {
            at = put(out, at, digits, n);
            at = put_zeros(out, at, (size_t)point - n);
        } else {
            at = put(out, at, digits, (size_t)point);
            out[at++] = '.';
            at = put(out, at, digits + point, n - (size_t)point);
        }
        return at;
    }
    out[at++] = digits[0];
    if (n > 1) {
        out[at++] = '.';
        at = put(out, at, digits + 1, n - 1);
    }
    out[at++] = 'e';
    if (exponent >= 0) {
        out[at++] = '+';
    }
    return at + msrt_fmt_i64(exponent, out + at);
}

static double bits_double(uint64_t bits) {
    double v;
    __builtin_memcpy(&v, &bits, sizeof v);
    return v;
}

size_t msrt_fmt_float(double v, uint8_t *out) {
    uint64_t bits;
    __builtin_memcpy(&bits, &v, sizeof bits);
    bool negative = (bits >> 63) != 0;
    double a = bits_double(bits & ~(UINT64_C(1) << 63));
    if (v != v) {
        return put_str(out, 0, "NaN");
    }
    if (a - a != 0.0) {
        return put_str(out, 0, negative ? "-Infinity" : "Infinity");
    }
    if (a == 0.0) {
        return put_str(out, 0, negative ? "-0" : "0");
    }
    uint8_t digits[24];
    int exp;
    size_t n;
    if (a < 9.007199254740992e15 && a == (double)(int64_t)a) {
        n = msrt_fmt_u64((uint64_t)a, digits);
        exp = (int)n - 1;
    } else {
        n = shortest(bits & ~(UINT64_C(1) << 63), 52, 1023, digits, &exp);
    }
    return render_decimal(digits, n, exp, negative, out);
}

size_t msrt_fmt_float32(double v, uint8_t *out) {
    float x = (float)v;
    if (x != x || x - x != 0.0f || x == 0.0f) {
        return msrt_fmt_float((double)x, out);
    }
    uint32_t bits;
    __builtin_memcpy(&bits, &x, sizeof bits);
    uint8_t digits[24];
    int exp;
    size_t n = shortest(bits & 0x7fffffffu, 23, 127, digits, &exp);
    return render_decimal(digits, n, exp, (bits >> 31) != 0, out);
}

/* ---- Precision forms: exact decimal expansion, rounded half to even ---- */

#define LIMB_BASE 1000000000u
#define MAX_LIMBS 96 /* c * 5^1074 has at most 2^53 * 10^751 < 10^768 */

/* The exact decimal digits of the positive finite value c * 2^q into digits (most significant first, no leading
 * zero); *point is the exponent of the first digit. Returns the digit count. */
static size_t exact_digits(uint64_t c, int q, uint8_t *digits, int *point) {
    uint32_t limb[MAX_LIMBS + 8];
    size_t n = 0;
    /* little-endian base 1e9 */
    for (uint64_t t = c; t != 0; t /= LIMB_BASE) {
        limb[n++] = (uint32_t)(t % LIMB_BASE);
    }
    int shift10 = 0; /* the value is limbs * 10^shift10 */
    if (q >= 0) {
        for (int i = 0; i < q; i++) {
            uint64_t carry = 0;
            for (size_t j = 0; j < n; j++) {
                uint64_t t = (uint64_t)limb[j] * 2 + carry;
                limb[j] = (uint32_t)(t % LIMB_BASE);
                carry = t / LIMB_BASE;
            }
            if (carry) {
                limb[n++] = (uint32_t)carry;
            }
        }
    } else {
        /* c * 2^q = c * 5^-q / 10^-q */
        for (int left = -q; left > 0;) {
            int step = left > 13 ? 13 : left;
            uint64_t m = 1;
            for (int i = 0; i < step; i++) {
                m *= 5;
            }
            uint64_t carry = 0;
            for (size_t j = 0; j < n; j++) {
                u128 t = (u128)limb[j] * m + carry;
                limb[j] = (uint32_t)(t % LIMB_BASE);
                carry = (uint64_t)(t / LIMB_BASE);
            }
            while (carry) {
                limb[n++] = (uint32_t)(carry % LIMB_BASE);
                carry /= LIMB_BASE;
            }
            left -= step;
        }
        shift10 = q;
    }
    size_t count = 0;
    uint8_t text[9];
    for (size_t j = n; j-- > 0;) {
        uint32_t t = limb[j];
        for (int i = 8; i >= 0; i--) {
            text[i] = (uint8_t)('0' + t % 10);
            t /= 10;
        }
        size_t from = 0;
        if (count == 0) {
            while (from < 8 && text[from] == '0') {
                from++;
            }
        }
        count = put(digits, count, text + from, 9 - from);
    }
    *point = (int)count - 1 + shift10;
    return count;
}

static bool any_nonzero(const uint8_t *digits, size_t n) {
    for (size_t i = 0; i < n; i++) {
        if (digits[i] != '0') {
            return true;
        }
    }
    return false;
}

/* Rounds the digit string to keep digits (half to even); returns the new exponent of the first digit and sets the
 * kept digits, padded with zeros, in out[0..keep]. */
static int round_digits(const uint8_t *digits, size_t n, int point, size_t keep, uint8_t *out) {
    for (size_t i = 0; i < keep; i++) {
        out[i] = i < n ? digits[i] : '0';
    }
    if (n <= keep) {
        return point;
    }
    bool up;
    if (digits[keep] != '5') {
        up = digits[keep] > '5';
    } else {
        up = any_nonzero(digits + keep + 1, n - keep - 1) || (keep > 0 && ((out[keep - 1] - '0') & 1));
    }
    if (up) {
        size_t i = keep;
        while (i > 0 && out[i - 1] == '9') {
            out[--i] = '0';
        }
        if (i == 0) {
            out[0] = '1';
            for (size_t j = 1; j < keep; j++) {
                out[j] = '0';
            }
            return point + 1;
        }
        out[i - 1]++;
    }
    return point;
}

/* The common case of to_fixed without the exact expansion: up to 15 fractional digits, a value below 2^53 in
 * magnitude, so c * 2^q * 10^digits is an integer product that fits 128 bits, divided by a power of two with the
 * remainder deciding the rounding (a tie goes to the even last digit). Returns false, writing nothing, when the
 * scaled result does not fit 64 bits or the value is not a fraction (q > 0). */
static bool fixed_fast(bool negative, uint64_t c, int q, size_t digits, uint8_t *out, size_t *len) {
    if (digits > 15 || q > 0) {
        return false;
    }
    uint64_t scale = 1;
    for (size_t i = 0; i < digits; i++) {
        scale *= 10;
    }
    u128 product = (u128)c * scale;
    unsigned shift = (unsigned)-q;
    u128 scaled;
    if (shift >= 128) {
        scaled = 0;
    } else if (shift == 0) {
        scaled = product;
    } else {
        u128 whole = product >> shift;
        u128 rest = product & (((u128)1 << shift) - 1);
        u128 half = (u128)1 << (shift - 1);
        scaled = whole + (rest > half || (rest == half && (whole & 1)));
    }
    if (scaled >> 64) {
        return false;
    }
    uint64_t total = (uint64_t)scaled;
    size_t at = 0;
    if (negative) {
        out[at++] = '-';
    }
    at += msrt_fmt_u64(total / scale, out + at);
    if (digits > 0) {
        out[at++] = '.';
        uint8_t frac[20];
        size_t n = msrt_fmt_u64(total % scale, frac);
        at = put_zeros(out, at, digits - n);
        at = put(out, at, frac, n);
    }
    *len = at;
    return true;
}

/* The scratch the exact expansion needs: 770 digits. */
#define EXACT_MAX 800

size_t msrt_fmt_float_precision(double v, uint8_t format, int64_t digits, uint8_t *out) {
    uint64_t bits;
    __builtin_memcpy(&bits, &v, sizeof bits);
    bool negative = (bits >> 63) != 0;
    double a = bits_double(bits & ~(UINT64_C(1) << 63));
    if (v != v || a - a != 0.0 || (format == 'f' && a >= 1e21)) {
        return msrt_fmt_float(v, out);
    }
    size_t want = (size_t)digits;
    int biased = (int)((bits >> 52) & 0x7ff);
    uint64_t fraction = bits & ((UINT64_C(1) << 52) - 1);
    uint64_t c = biased == 0 ? fraction : (fraction | (UINT64_C(1) << 52));
    int q = biased == 0 ? -1074 : biased - 1075;

    if (format == 'f') {
        size_t len;
        if (fixed_fast(negative, c, q, want, out, &len)) {
            return len;
        }
    }
    uint8_t exact[EXACT_MAX];
    uint8_t kept[EXACT_MAX];
    size_t n = 0;
    int point = 0;
    if (c != 0) {
        n = exact_digits(c, q, exact, &point);
    }
    size_t at = 0;
    if (negative) {
        out[at++] = '-';
    }
    if (format == 'f') {
        /* Digits are kept down to 10^-want. kept[i] has the exponent p - i. */
        int keep = point + 1 + (int)want;
        size_t len = 0;
        int p = point;
        if (c != 0 && keep > 0) {
            p = round_digits(exact, n, point, (size_t)keep, kept);
            len = (size_t)keep;
        } else if (c != 0 && keep == 0 && (exact[0] > '5' || (exact[0] == '5' && any_nonzero(exact + 1, n - 1)))) {
            /* Below one unit of the last place but above half of it: rounds up to that unit. */
            kept[0] = '1';
            len = 1;
            p = -(int)want;
        }
        if (p < 0 || len == 0) {
            out[at++] = '0';
        } else {
            for (int e = p; e >= 0; e--) {
                out[at++] = (size_t)(p - e) < len ? kept[p - e] : '0';
            }
        }
        if (want > 0) {
            out[at++] = '.';
            for (size_t i = 0; i < want; i++) {
                int idx = p + 1 + (int)i;
                out[at++] = len != 0 && idx >= 0 && (size_t)idx < len ? kept[idx] : '0';
            }
        }
        return at;
    }
    /* 'e': digits after the first; 'g': digits - 1 after the first */
    size_t after = format == 'g' ? want - 1 : want;
    int e10 = 0;
    if (c == 0) {
        for (size_t i = 0; i <= after; i++) {
            kept[i] = '0';
        }
    } else {
        e10 = round_digits(exact, n, point, after + 1, kept);
    }
    if (format == 'g' && e10 >= -6 && e10 < (int)want) {
        int pt = e10 + 1;
        if (pt <= 0) {
            at = put_str(out, at, "0.");
            at = put_zeros(out, at, (size_t)-pt);
        }
        for (size_t i = 0; i <= after; i++) {
            if (pt > 0 && i == (size_t)pt) {
                out[at++] = '.';
            }
            out[at++] = kept[i];
        }
        return at;
    }
    out[at++] = kept[0];
    if (after > 0) {
        out[at++] = '.';
        at = put(out, at, kept + 1, after);
    }
    out[at++] = 'e';
    if (e10 >= 0) {
        out[at++] = '+';
    }
    return at + msrt_fmt_i64(e10, out + at);
}

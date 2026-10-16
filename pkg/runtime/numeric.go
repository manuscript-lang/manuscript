package msruntime

import (
	"fmt"
	"math"
	"math/bits"
	"strconv"
	"strings"
)

// Checked Int arithmetic: overflow and division faults are Manuscript faults.
// Each operation is small enough for the compiler to inline.

func IntAdd(a, b int) int {
	r := a + b
	if (a^r)&(b^r) < 0 {
		intOverflow()
	}
	return r
}

func IntSubtract(a, b int) int {
	r := a - b
	if (a^b)&(a^r) < 0 {
		intOverflow()
	}
	return r
}

func IntMultiply(a, b int) int {
	if bits.UintSize == 32 {
		r := int64(a) * int64(b)
		if r != int64(int(r)) {
			intOverflow()
		}
		return int(r)
	}
	x, y := int64(a), int64(b)
	hi, lo := bits.Mul64(uint64(x), uint64(y))
	hi -= uint64((x>>63)&y) + uint64((y>>63)&x)
	if int64(hi) != int64(lo)>>63 {
		intOverflow()
	}
	return int(lo)
}

func IntDivide(a, b int) int {
	if b == 0 || a == math.MinInt && b == -1 {
		intDivisionFault(a, b)
	}
	return a / b
}

func IntRemainder(a, b int) int {
	if b == 0 {
		Raise("Int.%: remainder by zero; right must be nonzero, found 0")
	}
	if b == -1 {
		return 0
	}
	return a % b
}

func IntNegate(a int) int {
	if a == math.MinInt {
		intOverflow()
	}
	return -a
}

func intOverflow() {
	Raise(fmt.Sprintf("Int overflow; the result does not fit in signed %d bits, so bound the operands or use BigInt", bits.UintSize))
}

// FitInt converts a 64-bit host value (a size, count, or nanosecond tick) to
// Int, faulting where the platform's Int is narrower and cannot hold it.
func FitInt(v int64) int {
	if int64(int(v)) != v {
		intOverflow()
	}
	return int(v)
}

// clampInt is v limited to the platform's Int range, for host counters where
// saturation is more useful than a fault.
func clampInt(v int64) int {
	if int64(int(v)) != v {
		if v < 0 {
			return math.MinInt
		}
		return math.MaxInt
	}
	return int(v)
}

func FormatInt(v int) string   { return strconv.Itoa(v) }
func FormatBool(v bool) string { return strconv.FormatBool(v) }
func FormatFloat(v float64) string {
	switch {
	case math.IsNaN(v):
		return "NaN"
	case math.IsInf(v, 1):
		return "Infinity"
	case math.IsInf(v, -1):
		return "-Infinity"
	case v == 0 && math.Signbit(v):
		return "-0"
	case v == 0:
		return "0"
	}
	mantissa, exponent, _ := strings.Cut(strconv.FormatFloat(math.Abs(v), 'e', -1, 64), "e")
	e, _ := strconv.Atoi(exponent)
	return renderDecimal(strings.ReplaceAll(mantissa, ".", ""), e, math.Signbit(v))
}

func renderDecimal(digits string, exponent int, negative bool) string {
	sign := ""
	if negative {
		sign = "-"
	}
	digits = strings.TrimRight(digits, "0")
	if exponent >= -6 && exponent <= 20 {
		point := exponent + 1
		if point <= 0 {
			return sign + "0." + strings.Repeat("0", -point) + digits
		}
		if point >= len(digits) {
			return sign + digits + strings.Repeat("0", point-len(digits))
		}
		return sign + digits[:point] + "." + digits[point:]
	}
	out := sign + digits[:1]
	if len(digits) > 1 {
		out += "." + digits[1:]
	}
	exp := strconv.Itoa(exponent)
	if exponent >= 0 {
		exp = "+" + exp
	}
	return out + "e" + exp
}

func intDivisionFault(a, b int) {
	if b == 0 {
		Raise("Int./: division by zero; right must be nonzero, found 0")
	}
	Raise(fmt.Sprintf("Int./: overflow; found left %d and right %d; result must be between %d and %d", a, b, math.MinInt, math.MaxInt))
}

// Equals is == for types Go compares directly.
func Equals[T comparable](_ *Execution, a, b T) bool { return a == b }

// Float returns x unchanged; the compiler cannot fold a call to it, so IEEE
// division by zero and overflow of literal operands happen at run time.
func Float(x float64) float64 { return x }

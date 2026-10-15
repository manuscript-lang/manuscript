package rt

import (
	"math"
	"math/bits"
	"strconv"

	msruntime "github.com/manuscript-lang/manuscript/pkg/runtime"
)

// Checked Int arithmetic: overflow and division faults are Manuscript faults.
// Each operation is small enough for the compiler to inline.

func IntAdd(a, b int64) int64 {
	r := a + b
	if (a^r)&(b^r) < 0 {
		intOverflow()
	}
	return r
}

func IntSubtract(a, b int64) int64 {
	r := a - b
	if (a^b)&(a^r) < 0 {
		intOverflow()
	}
	return r
}

func IntMultiply(a, b int64) int64 {
	hi, lo := bits.Mul64(uint64(a), uint64(b))
	hi -= uint64((a>>63)&b) + uint64((b>>63)&a)
	if int64(hi) != int64(lo)>>63 {
		intOverflow()
	}
	return int64(lo)
}

func IntDivide(a, b int64) int64 {
	if b == 0 || a == math.MinInt64 && b == -1 {
		return msruntime.IntDivide(a, b)
	}
	return a / b
}

func IntRemainder(a, b int64) int64 {
	if b == 0 {
		return msruntime.IntRemainder(a, b)
	}
	if b == -1 {
		return 0
	}
	return a % b
}

func IntNegate(a int64) int64 {
	if a == math.MinInt64 {
		intOverflow()
	}
	return -a
}

func intOverflow() {
	msruntime.Panic("Int overflow; the result does not fit in signed 64 bits, so bound the operands or use BigInt")
}

func FormatInt(v int64) string  { return strconv.FormatInt(v, 10) }
func FormatBool(v bool) string  { return strconv.FormatBool(v) }
func FormatFloat(v float64) string { return msruntime.Format(v) }

// Equals is == for types Go compares directly.
func Equals[T comparable](_ *Execution, a, b T) bool { return a == b }

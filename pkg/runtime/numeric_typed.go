package msruntime

import (
	"fmt"
	"math"
	"math/bits"
)

// Scalar extraction and checked operations let generated numeric expressions
// stay typed between operations, while values at language boundaries stay boxed.
func IntValue(value Value) int64     { return value.(int64) }
func FloatValue(value Value) float64 { return value.(float64) }
func IntAdd(a, b int64) int64        { return checkedAdd(a, b) }
func IntSubtract(a, b int64) int64   { return checkedSub(a, b) }
func IntMultiply(a, b int64) int64   { return checkedMul(a, b) }

func IntDivide(a, b int64) int64 {
	if b == 0 || a == math.MinInt64 && b == -1 {
		intDivisionFault(a, b)
	}
	return a / b
}

func intDivisionFault(a, b int64) {
	if b == 0 {
		Panic("Int./: division by zero; right must be nonzero, found 0")
	}
	Panic(fmt.Sprintf("Int./: overflow; found left %d and right %d; result must be between %d and %d", a, b, math.MinInt64, math.MaxInt64))
}

func IntRemainder(a, b int64) int64 {
	if b == 0 {
		Panic("Int.%: remainder by zero; right must be nonzero, found 0")
	}
	return a % b
}

func StringValue(value Value) string { return value.(string) }

// The *At variants check overflow and division inline and leave the fault to
// the unchecked operation, so both forms report identical messages.
func IntAddAt(a, b int64) int64 {
	r := a + b
	if (a^r)&(b^r) < 0 {
		intOverflow()
	}
	return r
}

func IntSubtractAt(a, b int64) int64 {
	r := a - b
	if (a^b)&(a^r) < 0 {
		intOverflow()
	}
	return r
}

// intOverflow raises the fault of Int addition and subtraction.
func intOverflow() {
	Panic("Int overflow; the result does not fit in signed 64 bits, so bound the operands or use BigInt")
}

func IntMultiplyAt(a, b int64) int64 {
	hi, lo := bits.Mul64(uint64(a), uint64(b))
	hi -= uint64((a>>63)&b) + uint64((b>>63)&a)
	if int64(hi) != int64(lo)>>63 {
		return IntMultiply(a, b)
	}
	return int64(lo)
}

func IntDivideAt(a, b int64) int64 {
	if b == 0 || a == math.MinInt64 && b == -1 {
		return IntDivide(a, b)
	}
	return a / b
}

// IntNegateAt negates a, faulting when -a overflows.
func IntNegateAt(a int64) int64 {
	if a == math.MinInt64 {
		Unary("-", a)
	}
	return -a
}

func IntRemainderAt(a, b int64) int64 {
	if b == 0 {
		return IntRemainder(a, b)
	}
	if b == -1 {
		return 0
	}
	return a % b
}

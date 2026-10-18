package msruntime

import "math/bits"

func Bits_BitAnd(_ *Execution, left, right int) int { return left & right }
func Bits_BitOr(_ *Execution, left, right int) int  { return left | right }
func Bits_BitXor(_ *Execution, left, right int) int { return left ^ right }
func Bits_BitNot(_ *Execution, value int) int       { return ^value }

func bitsCount(operation string, count int) uint {
	if count < 0 || count > 63 {
		rangeFault(operation, "count", count, 0, 63)
	}
	return uint(count)
}

func Bits_ShiftLeft(_ *Execution, value, count int) int {
	return value << bitsCount("shift_left", count)
}

func Bits_ShiftRight(_ *Execution, value, count int) int {
	return value >> bitsCount("shift_right", count)
}

func Bits_ShiftRightUnsigned(_ *Execution, value, count int) int {
	return int(uint64(value) >> bitsCount("shift_right_unsigned", count))
}

func Bits_RotateLeft(_ *Execution, value, count int) int {
	return int(bits.RotateLeft64(uint64(value), count%64))
}

func Bits_RotateRight(_ *Execution, value, count int) int {
	return int(bits.RotateLeft64(uint64(value), -(count % 64)))
}

func Bits_CountOnes(_ *Execution, value int) int     { return bits.OnesCount64(uint64(value)) }
func Bits_LeadingZeros(_ *Execution, value int) int  { return bits.LeadingZeros64(uint64(value)) }
func Bits_TrailingZeros(_ *Execution, value int) int { return bits.TrailingZeros64(uint64(value)) }

func Bits_WrappingAdd(_ *Execution, left, right int) int      { return left + right }
func Bits_WrappingSubtract(_ *Execution, left, right int) int { return left - right }
func Bits_WrappingMultiply(_ *Execution, left, right int) int { return left * right }

package msruntime

import (
	"fmt"
	"math"
	"math/big"
)

func init() { installNumericParity() }

func installNumericParity() {
	p := func(name, typ string) LibraryParam { return LibraryParam{name, typ} }
	for _, name := range []string{"min_int", "max_int"} {
		libraryAdd("math", name, "Int", []LibraryParam{p("left", "Int"), p("right", "Int")}, func(_ *Execution, _ string, args []Value) Value {
			left, right := args[0].(int64), args[1].(int64)
			if name == "min_int" {
				return min(left, right)
			}
			return max(left, right)
		})
	}
	libraryAdd("math", "pow_int", libraryResult("Int", "NumberError"), []LibraryParam{p("base", "Int"), p("exponent", "Int")}, func(ctx *Execution, result string, args []Value) Value {
		base, exponent := args[0].(int64), args[1].(int64)
		if exponent < 0 {
			return libraryError(result, "InvalidInput", "")
		}
		out := int64(1)
		for exponent > 0 {
			CheckCancelled(ctx)
			var valid bool
			if exponent&1 != 0 {
				out, valid = numericMultiplyInt(out, base)
				if !valid {
					return libraryError(result, "OutOfRange", "")
				}
			}
			exponent >>= 1
			if exponent > 0 {
				base, valid = numericMultiplyInt(base, base)
				if !valid {
					return libraryError(result, "OutOfRange", "")
				}
			}
		}
		return libraryOK(result, out)
	})
	libraryAdd("math", "sign", "Float", []LibraryParam{p("value", "Float")}, func(_ *Execution, _ string, args []Value) Value {
		value := args[0].(float64)
		if value == 0 || math.IsNaN(value) {
			return value
		}
		return math.Copysign(1, value)
	})
	libraryAdd("math", "sign_int", "Int", []LibraryParam{p("value", "Int")}, func(_ *Execution, _ string, args []Value) Value {
		value := args[0].(int64)
		if value < 0 {
			return int64(-1)
		}
		if value > 0 {
			return int64(1)
		}
		return int64(0)
	})
	libraryAdd("math", "clamp", "Float", []LibraryParam{p("value", "Float"), p("minimum", "Float"), p("maximum", "Float")}, func(_ *Execution, _ string, args []Value) Value {
		value, minimum, maximum := args[0].(float64), args[1].(float64), args[2].(float64)
		if minimum > maximum {
			return Panic(fmt.Sprintf("math.clamp: minimum must be <= maximum; found minimum %s and maximum %s", formatFloat(minimum), formatFloat(maximum)))
		}
		return math.Max(minimum, math.Min(value, maximum))
	})
	libraryAdd("math", "clamp_int", "Int", []LibraryParam{p("value", "Int"), p("minimum", "Int"), p("maximum", "Int")}, func(_ *Execution, _ string, args []Value) Value {
		value, minimum, maximum := args[0].(int64), args[1].(int64), args[2].(int64)
		if minimum > maximum {
			return Panic(fmt.Sprintf("math.clamp_int: minimum must be <= maximum; found minimum %d and maximum %d", minimum, maximum))
		}
		return max(minimum, min(value, maximum))
	})
	for name, operation := range map[string]func(float64) float64{
		"cbrt": math.Cbrt, "asinh": math.Asinh, "acosh": math.Acosh, "atanh": math.Atanh,
	} {
		libraryAdd("math", name, "Float", []LibraryParam{p("value", "Float")}, func(_ *Execution, _ string, args []Value) Value { return operation(args[0].(float64)) })
	}
	for name, operation := range map[string]func(float64) float64{
		"round_to_int": javascriptRound, "floor_to_int": math.Floor, "ceil_to_int": math.Ceil,
	} {
		libraryAdd("math", name, "Optional[Int]", []LibraryParam{p("value", "Float")}, func(_ *Execution, _ string, args []Value) Value {
			value := operation(args[0].(float64))
			if math.IsNaN(value) || math.IsInf(value, 0) || value < -9223372036854775808.0 || value >= 9223372036854775808.0 {
				return optional("Int", nil, false)
			}
			return optional("Int", int64(value), true)
		})
	}
	libraryAdd("math", "sum_int", libraryResult("Int", "NumberError"), []LibraryParam{p("values", "List[Int]")}, func(ctx *Execution, result string, args []Value) Value {
		CheckCancelled(ctx)
		items := args[0].(*List).Items
		out := int64(0)
		for i, value := range items {
			if i%256 == 0 {
				CheckCancelled(ctx)
			}
			number := value.(int64)
			if number > 0 && out > math.MaxInt64-number || number < 0 && out < math.MinInt64-number {
				return libraryError(result, "OutOfRange", "")
			}
			out += number
		}
		CheckCancelled(ctx)
		return libraryOK(result, out)
	})
	libraryAdd("math", "sum_float", "Float", []LibraryParam{p("values", "List[Float]")}, func(ctx *Execution, _ string, args []Value) Value {
		CheckCancelled(ctx)
		items := args[0].(*List).Items
		out := float64(0)
		for i, value := range items {
			if i%256 == 0 {
				CheckCancelled(ctx)
			}
			out += value.(float64)
		}
		CheckCancelled(ctx)
		return out
	})
	for name, operation := range map[string]func(*big.Int, *big.Int) *big.Int{
		"negate": (*big.Int).Neg, "abs": (*big.Int).Abs, "bit_not": (*big.Int).Not,
	} {
		libraryAdd("bigint", name, "BigInt", []LibraryParam{p("value", "BigInt")}, func(_ *Execution, _ string, args []Value) Value {
			return libraryBigInt{operation(new(big.Int), args[0].(libraryBigInt).n)}
		})
	}
	libraryAdd("bigint", "pow", libraryResult("BigInt", "BigIntError"), []LibraryParam{p("value", "BigInt"), p("exponent", "Int"), p("max_bits", "Optional[Int]")}, numericBigIntPow)
	libraryAdd("bigint", "shift_left", libraryResult("BigInt", "BigIntError"), []LibraryParam{p("value", "BigInt"), p("count", "Int"), p("max_bits", "Optional[Int]")}, func(ctx *Execution, result string, args []Value) Value {
		value, count, limit := args[0].(libraryBigInt).n, args[1].(int64), args[2].(int64)
		if count < 0 || limit < 0 {
			return libraryError(result, "InvalidInput", "")
		}
		limit = min(limit, numericMaxBigIntBits)
		if value.Sign() != 0 && (count > limit || int64(value.BitLen()) > limit-count) {
			return libraryError(result, "LimitExceeded", "")
		}
		CheckCancelled(ctx)
		out := new(big.Int)
		if value.Sign() != 0 {
			out.Lsh(value, uint(count))
		}
		CheckCancelled(ctx)
		return libraryOK(result, libraryBigInt{out})
	})
	libraryAdd("bigint", "shift_right", libraryResult("BigInt", "BigIntError"), []LibraryParam{p("value", "BigInt"), p("count", "Int")}, func(ctx *Execution, result string, args []Value) Value {
		value, count := args[0].(libraryBigInt).n, args[1].(int64)
		if count < 0 {
			return libraryError(result, "InvalidInput", "")
		}
		CheckCancelled(ctx)
		out := new(big.Int)
		if count >= int64(value.BitLen()) {
			if value.Sign() < 0 {
				out.SetInt64(-1)
			}
		} else {
			out.Rsh(value, uint(count))
		}
		CheckCancelled(ctx)
		return libraryOK(result, libraryBigInt{out})
	})
	libraryAdd("decimal", "abs", "Decimal", []LibraryParam{p("value", "Decimal")}, func(_ *Execution, _ string, args []Value) Value {
		return Decimal{new(big.Rat).Abs(args[0].(Decimal).Value)}
	})
	libraryAdd("decimal", "compare", "Int", []LibraryParam{p("left", "Decimal"), p("right", "Decimal")}, func(_ *Execution, _ string, args []Value) Value {
		return int64(args[0].(Decimal).Value.Cmp(args[1].(Decimal).Value))
	})
	for name, mode := range map[string]string{"floor_to_int": "Floor", "ceil_to_int": "Ceil", "round_to_int": "HalfEven"} {
		libraryAdd("decimal", name, "Optional[Int]", []LibraryParam{p("value", "Decimal")}, func(_ *Execution, _ string, args []Value) Value {
			coefficient, _ := decimalRoundedCoefficient(args[0].(Decimal), 0, mode)
			return optional("Int", coefficient.Int64(), coefficient.IsInt64())
		})
	}
}

func numericMultiplyInt(left, right int64) (int64, bool) {
	if left == 0 || right == 0 {
		return 0, true
	}
	if left == math.MinInt64 && right == -1 || right == math.MinInt64 && left == -1 {
		return 0, false
	}
	product := left * right
	return product, product/right == left
}

// Growth APIs refuse results above 32 MiB of magnitude bits even without a
// caller budget. Intermediate products are preflighted before they allocate.
const numericMaxBigIntBits = int64(1 << 28)

func numericBigIntPow(ctx *Execution, result string, args []Value) Value {
	base, exponent, limit := args[0].(libraryBigInt).n, args[1].(int64), args[2].(int64)
	if exponent < 0 || limit < 0 {
		return libraryError(result, "InvalidInput", "")
	}
	limit = min(limit, numericMaxBigIntBits)
	CheckCancelled(ctx)
	out := big.NewInt(1)
	if exponent > 0 && base.Sign() == 0 {
		out.SetInt64(0)
	} else if exponent > 0 {
		if int64(base.BitLen()) > limit {
			return libraryError(result, "LimitExceeded", "")
		}
		// |base| >= 2^(BitLen-1), so this lower bound rules out huge
		// exponents before any repeated-squaring allocation is necessary.
		if bits := int64(base.BitLen()); bits > 1 && exponent > (limit-1)/(bits-1) {
			return libraryError(result, "LimitExceeded", "")
		}
		factor := new(big.Int).Set(base)
		for exponent > 0 {
			CheckCancelled(ctx)
			if exponent&1 != 0 && !numericMultiplyBigInt(out, out, factor, limit) {
				return libraryError(result, "LimitExceeded", "")
			}
			exponent >>= 1
			if exponent > 0 && !numericMultiplyBigInt(factor, factor, factor, limit) {
				return libraryError(result, "LimitExceeded", "")
			}
		}
	}
	if int64(out.BitLen()) > limit {
		return libraryError(result, "LimitExceeded", "")
	}
	CheckCancelled(ctx)
	return libraryOK(result, libraryBigInt{out})
}

func numericMultiplyBigInt(out, left, right *big.Int, limit int64) bool {
	if left.Sign() != 0 && right.Sign() != 0 && int64(left.BitLen())+int64(right.BitLen())-1 > limit {
		return false
	}
	out.Mul(left, right)
	return int64(out.BitLen()) <= limit
}

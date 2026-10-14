package msruntime

import (
	"fmt"
	"github.com/manuscript-lang/manuscript/internal/decimal"
	"math"
	"math/big"
	"strconv"
	"strings"
)

func checkedAdd(a, b int64) int64 {
	r := a + b
	if b > 0 && r < a || b < 0 && r > a {
		Panic("Int overflow; the result does not fit in signed 64 bits, so bound the operands or use BigInt")
	}
	return r
}
func checkedSub(a, b int64) int64 {
	r := a - b
	if b < 0 && r < a || b > 0 && r > a {
		Panic("Int overflow; the result does not fit in signed 64 bits, so bound the operands or use BigInt")
	}
	return r
}
func checkedMul(a, b int64) int64 {
	if a == 0 || b == 0 {
		return 0
	}
	if a == math.MinInt64 && b == -1 || b == math.MinInt64 && a == -1 {
		Panic("Int overflow; the result does not fit in signed 64 bits, so bound the operands or use BigInt")
	}
	r := a * b
	if r/b != a {
		Panic("Int overflow; the result does not fit in signed 64 bits, so bound the operands or use BigInt")
	}
	return r
}
func Unary(op string, value Value) Value {
	switch op {
	case "not":
		return !Bool(value)
	case "try":
		return Try(value)
	case "+":
		return value
	case "-":
		switch v := value.(type) {
		case int64:
			if v == math.MinInt64 {
				return Panic("Int overflow; the result does not fit in signed 64 bits, so bound the operands or use BigInt")
			}
			return -v
		case float64:
			return -v
		case Decimal:
			return Decimal{new(big.Rat).Neg(v.Value)}
		}
	}
	return Panic("runtime invariant: unary operator")
}
func Binary(op string, a, b Value) Value {
	if op == "==" {
		return Equal(a, b)
	}
	if op == "!=" {
		return !Equal(a, b)
	}
	switch x := a.(type) {
	case string:
		y := b.(string)
		switch op {
		case "+":
			return x + y
		case "<":
			return x < y
		case "<=":
			return x <= y
		case ">":
			return x > y
		case ">=":
			return x >= y
		}
	case int64:
		y := b.(int64)
		switch op {
		case "+":
			return checkedAdd(x, y)
		case "-":
			return checkedSub(x, y)
		case "*":
			return checkedMul(x, y)
		case "/":
			return IntDivide(x, y)
		case "%":
			return IntRemainder(x, y)
		case "<":
			return x < y
		case "<=":
			return x <= y
		case ">":
			return x > y
		case ">=":
			return x >= y
		}
	case float64:
		y := b.(float64)
		switch op {
		case "+":
			return x + y
		case "-":
			return x - y
		case "*":
			return x * y
		case "/":
			return x / y
		case "<":
			return x < y
		case "<=":
			return x <= y
		case ">":
			return x > y
		case ">=":
			return x >= y
		}
	case Decimal:
		y := b.(Decimal)
		cmp := x.Value.Cmp(y.Value)
		switch op {
		case "<":
			return cmp < 0
		case "<=":
			return cmp <= 0
		case ">":
			return cmp > 0
		case ">=":
			return cmp >= 0
		}
		result := new(big.Rat)
		switch op {
		case "+":
			result.Add(x.Value, y.Value)
		case "-":
			result.Sub(x.Value, y.Value)
		case "*":
			result.Mul(x.Value, y.Value)
		case "/":
			if y.Value.Sign() == 0 {
				return Panic("Decimal./: division by zero; right must be nonzero, found 0")
			}
			result.Quo(x.Value, y.Value)
		}
		return roundDecimal(result, op, x, y)
	case Duration:
		y := b.(Duration)
		switch op {
		case "+":
			return Duration(checkedTimeAdd("Duration.+", "left", "right", int64(x), int64(y)))
		case "-":
			return Duration(checkedTimeSub("Duration.-", "left", "right", int64(x), int64(y)))
		case "<":
			return x < y
		case "<=":
			return x <= y
		case ">":
			return x > y
		case ">=":
			return x >= y
		}
	case Instant:
		if y, ok := b.(Instant); ok {
			sameClock(x, y)
			switch op {
			case "-":
				return Duration(checkedTimeSub("Instant.-", "left", "right", x.Tick, y.Tick))
			case "<":
				return x.Tick < y.Tick
			case "<=":
				return x.Tick <= y.Tick
			case ">":
				return x.Tick > y.Tick
			case ">=":
				return x.Tick >= y.Tick
			}
		}
		y := b.(Duration)
		if op == "+" {
			return Instant{x.Domain, checkedTimeAdd("Instant.+", "value", "duration", x.Tick, int64(y))}
		}
		return Instant{x.Domain, checkedTimeSub("Instant.-", "value", "duration", x.Tick, int64(y))}
	}
	return Panic("runtime invariant: binary operator")
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
func formatFloat(v float64) string {
	if math.IsNaN(v) {
		return "NaN"
	}
	if math.IsInf(v, 1) {
		return "Infinity"
	}
	if math.IsInf(v, -1) {
		return "-Infinity"
	}
	if v == 0 {
		if math.Signbit(v) {
			return "-0"
		}
		return "0"
	}
	negative := math.Signbit(v)
	mantissa, exponent, _ := strings.Cut(strconv.FormatFloat(math.Abs(v), 'e', -1, 64), "e")
	e, _ := strconv.Atoi(exponent)
	return renderDecimal(strings.ReplaceAll(mantissa, ".", ""), e, negative)
}

func duration(value Value, name string) Value {
	scale := int64(1000000)
	if name == "seconds" {
		scale = 1000000000
	}
	if name == "minutes" {
		scale = 60000000000
	}
	n := value.(int64)
	if n < math.MinInt64/scale || n > math.MaxInt64/scale {
		return libraryRangeFault("Int."+name, "value", n, math.MinInt64/scale, math.MaxInt64/scale)
	}
	return Duration(n * scale)
}

type Decimal struct{ Value *big.Rat }

func DecimalLiteral(text string) Value {
	coefficient, exponent, negative, valid := decimal.Parts(text)
	if !valid {
		return Panic("invalid or inexact Decimal literal")
	}
	if coefficient == "0" {
		return Decimal{new(big.Rat)}
	}
	if negative {
		coefficient = "-" + coefficient
	}
	value, ok := new(big.Rat).SetString(coefficient + "e" + strconv.Itoa(exponent))
	if !ok {
		return Panic("invalid Decimal literal")
	}
	return Decimal{value}
}

func pow10(n int) *big.Int { return new(big.Int).Exp(big.NewInt(10), big.NewInt(int64(n)), nil) }
func decimalExponent(r *big.Rat) int {
	if r.Sign() == 0 {
		return 0
	}
	n := new(big.Int).Abs(r.Num())
	d := r.Denom()
	e := len(n.String()) - len(d.String())
	if e >= 0 {
		if n.Cmp(new(big.Int).Mul(d, pow10(e))) < 0 {
			e--
		}
	} else {
		if new(big.Int).Mul(n, pow10(-e)).Cmp(d) < 0 {
			e--
		}
	}
	return e
}
func roundDecimal(r *big.Rat, operation string, left, right Decimal) Decimal {
	if r.Sign() == 0 {
		return Decimal{new(big.Rat)}
	}
	e := decimalExponent(r)
	q := e - 33
	if q < -6176 {
		q = -6176
	}
	scaled := new(big.Rat).Abs(r)
	if q >= 0 {
		scaled.Quo(scaled, new(big.Rat).SetInt(pow10(q)))
	} else {
		scaled.Mul(scaled, new(big.Rat).SetInt(pow10(-q)))
	}
	coefficient, remainder := new(big.Int), new(big.Int)
	coefficient.QuoRem(scaled.Num(), scaled.Denom(), remainder)
	twice := new(big.Int).Lsh(remainder, 1)
	cmp := twice.Cmp(scaled.Denom())
	if cmp > 0 || cmp == 0 && coefficient.Bit(0) == 1 {
		coefficient.Add(coefficient, big.NewInt(1))
	}
	if r.Sign() < 0 {
		coefficient.Neg(coefficient)
	}
	out := new(big.Rat).SetInt(coefficient)
	if q >= 0 {
		out.Mul(out, new(big.Rat).SetInt(pow10(q)))
	} else {
		out.Quo(out, new(big.Rat).SetInt(pow10(-q)))
	}
	if out.Sign() != 0 && decimalExponent(out) > 6144 {
		Panic(fmt.Sprintf("Decimal.%s: overflow; found left %s and right %s; rounded magnitude must be at most 9.999999999999999999999999999999999e6144 (34 significant digits)", operation, left.String(), right.String()))
	}
	return Decimal{out}
}
func (d Decimal) String() string {
	if d.Value.Sign() == 0 {
		return "0"
	}
	e := decimalExponent(d.Value)
	q := e - 33
	scaled := new(big.Rat).Abs(d.Value)
	if q >= 0 {
		scaled.Quo(scaled, new(big.Rat).SetInt(pow10(q)))
	} else {
		scaled.Mul(scaled, new(big.Rat).SetInt(pow10(-q)))
	}
	return renderDecimal(scaled.Num().String(), e, d.Value.Sign() < 0)
}

// ValidateDecimalLiteral checks exactness independently of runtime rounding.
func ValidateDecimalLiteral(text string) bool {
	_, _, _, valid := decimal.Parts(text)
	return valid
}

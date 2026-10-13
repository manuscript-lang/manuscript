package msruntime

import (
	"fmt"
	"math"
	"math/big"
	"strconv"
)

// Explicit wide scalars have distinct dynamic identities at every Value boundary.
// They must never be mistaken for a default-width value in generic/native code.
type Int64 int64
type Float64 float64

func wideOverflow(operation string) Value {
	return Panic("Int64 " + operation + " overflow: result outside signed 64-bit range; bound the operands or use BigInt")
}

func integer64Binary(op string, x, y Int64) Value {
	switch op {
	case "+":
		r := x + y
		if y > 0 && r < x || y < 0 && r > x {
			return wideOverflow(op)
		}
		return r
	case "-":
		r := x - y
		if y < 0 && r < x || y > 0 && r > x {
			return wideOverflow(op)
		}
		return r
	case "*":
		if x == 0 || y == 0 {
			return Int64(0)
		}
		if x == math.MinInt64 && y == -1 || y == math.MinInt64 && x == -1 {
			return wideOverflow(op)
		}
		r := x * y
		if r/y != x {
			return wideOverflow(op)
		}
		return r
	case "/", "%":
		if y == 0 {
			return Panic(fmt.Sprintf("Int64 %s: division by zero; divisor must be nonzero, found 0", op))
		}
		if op == "%" {
			return x % y
		}
		if x == math.MinInt64 && y == -1 {
			return wideOverflow(op)
		}
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
	return Panic("runtime invariant: Int64 binary operator")
}

func float64Binary(op string, x, y Float64) Value {
	switch op {
	case "+":
		return Float64(float64(x) + float64(y))
	case "-":
		return Float64(float64(x) - float64(y))
	case "*":
		return Float64(float64(x) * float64(y))
	case "/":
		return Float64(float64(x) / float64(y))
	case "<":
		return x < y
	case "<=":
		return x <= y
	case ">":
		return x > y
	case ">=":
		return x >= y
	}
	return Panic("runtime invariant: Float64 binary operator")
}

func truncateInt64(value float64) Value {
	// +2^63 is exactly representable as Float64; MaxInt64 is not. Check the
	// mathematical half-open range after truncation, before the host cast.
	value = math.Trunc(value)
	if math.IsNaN(value) || math.IsInf(value, 0) || value >= 0x1p63 || value < -0x1p63 {
		return optional("Int64", nil, false)
	}
	return optional("Int64", Int64(value), true)
}

func wideNumericMember(receiver Value, name, result string) (Value, bool) {
	labels := []string{}
	available := false
	switch receiver.(type) {
	case int32:
		available = name == "to_int64" || name == "to_float64"
	case float32:
		available = name == "to_float64" || name == "truncate_to_int64"
	case Int64:
		available = name == "to_int" || name == "to_float" || name == "to_float64" || name == "to_decimal" || name == "to_string"
		if name == "to_string" {
			labels = []string{"radix"}
		}
	case Float64:
		available = name == "to_float" || name == "truncate_to_int" || name == "truncate_to_int64" || name == "to_string" || name == "is_nan" || name == "is_finite" || name == "to_precision" || name == "to_exponential" || name == "to_fixed"
		if name == "to_precision" {
			labels = []string{"precision"}
		}
		if name == "to_exponential" || name == "to_fixed" {
			labels = []string{"digits"}
		}
	}
	if !available {
		return nil, false
	}
	return NewFunction(labels, result, func(_ *Execution, args []Value) Value {
		switch v := receiver.(type) {
		case int32:
			if name == "to_int64" {
				return Int64(v)
			}
			return Float64(v)
		case float32:
			if name == "to_float64" {
				return Float64(v)
			}
			return truncateInt64(float64(v))
		case Int64:
			switch name {
			case "to_int":
				if v < math.MinInt32 || v > math.MaxInt32 {
					return optional("Int", nil, false)
				}
				return optional("Int", int32(v), true)
			case "to_float":
				return float32(v)
			case "to_float64":
				return Float64(v)
			case "to_decimal":
				return Decimal{new(big.Rat).SetInt64(int64(v))}
			case "to_string":
				radix := nativeInteger(args[0])
				if radix < 2 || radix > 36 {
					return libraryRangeFault("Int64.to_string", "radix", radix, 2, 36)
				}
				return strconv.FormatInt(int64(v), int(radix))
			}
		case Float64:
			f := float64(v)
			switch name {
			case "to_float":
				return float32(f)
			case "truncate_to_int64":
				return truncateInt64(f)
			case "truncate_to_int":
				return truncateInt32(f)
			case "to_string":
				return formatFloat(f)
			case "is_nan":
				return math.IsNaN(f)
			case "is_finite":
				return !math.IsNaN(f) && !math.IsInf(f, 0)
			case "to_precision", "to_exponential", "to_fixed":
				precision := nativeInteger(args[0])
				minimum := int64(0)
				format := byte('f')
				if name == "to_precision" {
					minimum, format = 1, 'g'
				}
				if name == "to_exponential" {
					format = 'e'
				}
				typ := "@std/Result[String][@std/NumberError]"
				if precision < minimum || precision > 100 {
					return libraryError(typ, "InvalidInput", "")
				}
				return libraryOK(typ, formatFloatPrecision(f, format, int(precision)))
			}
		}
		return Panic("runtime invariant: explicit wide numeric operation")
	}), true
}

func init() {
	p := func(name, typ string) LibraryParam { return LibraryParam{name, typ} }
	libraryAdd("numbers", "parse_int64", libraryResult("Int64", "NumberError"), []LibraryParam{p("text", "String"), p("radix", "Int")}, func(_ *Execution, result string, args []Value) Value {
		radix := nativeInteger(args[1])
		if radix < 2 || radix > 36 {
			return libraryError(result, "InvalidInput", "")
		}
		text := args[0].(string)
		if !libraryIntegerSyntax(text, int(radix)) {
			return libraryError(result, "InvalidData", "")
		}
		n, err := strconv.ParseInt(text, int(radix), 64)
		if err != nil {
			return libraryError(result, "OutOfRange", "")
		}
		return libraryOK(result, Int64(n))
	})
	libraryAdd("numbers", "parse_float64", libraryResult("Float64", "NumberError"), []LibraryParam{p("text", "String")}, func(_ *Execution, result string, args []Value) Value {
		text := args[0].(string)
		if !libraryFloatSyntax.MatchString(text) && text != "NaN" && text != "Infinity" && text != "-Infinity" {
			return libraryError(result, "InvalidData", "")
		}
		n, err := strconv.ParseFloat(text, 64)
		if err != nil {
			return libraryError(result, "OutOfRange", "")
		}
		return libraryOK(result, Float64(n))
	})
}

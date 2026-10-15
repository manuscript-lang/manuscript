package msruntime

import (
	"math"
	"strconv"
	"strings"
	"unicode/utf8"
)

// Typed implementations of pure scalar standard functions. The library table
// wraps them for dynamic calls, and generated code calls them directly when the
// callee and argument types are static, so both paths share one body.
func MathAbs(value float64) float64             { return math.Abs(value) }
func MathFloor(value float64) float64           { return math.Floor(value) }
func MathCeil(value float64) float64            { return math.Ceil(value) }
func MathRound(value float64) float64           { return roundHalfUp(value) }
func MathSqrt(value float64) float64            { return math.Sqrt(value) }
func MathExp(value float64) float64             { return math.Exp(value) }
func MathLog(value float64) float64             { return math.Log(value) }
func MathLog2(value float64) float64            { return math.Log2(value) }
func MathLog10(value float64) float64           { return math.Log10(value) }
func MathSin(value float64) float64             { return math.Sin(value) }
func MathCos(value float64) float64             { return math.Cos(value) }
func MathTan(value float64) float64             { return math.Tan(value) }
func MathAsin(value float64) float64            { return math.Asin(value) }
func MathAcos(value float64) float64            { return math.Acos(value) }
func MathAtan(value float64) float64            { return math.Atan(value) }
func MathSinh(value float64) float64            { return math.Sinh(value) }
func MathCosh(value float64) float64            { return math.Cosh(value) }
func MathTanh(value float64) float64            { return math.Tanh(value) }
func MathTruncate(value float64) float64        { return math.Trunc(value) }
func MathPow(base, exponent float64) float64    { return math.Pow(base, exponent) }
func MathMin(left, right float64) float64       { return math.Min(left, right) }
func MathMax(left, right float64) float64       { return math.Max(left, right) }
func MathHypot(left, right float64) float64     { return math.Hypot(left, right) }
func MathAtan2(y, x float64) float64            { return math.Atan2(y, x) }
func MathRemainder(left, right float64) float64 { return math.Mod(left, right) }
func MathIsNaN(value float64) bool              { return math.IsNaN(value) }
func MathIsFinite(value float64) bool           { return !math.IsNaN(value) && !math.IsInf(value, 0) }

func MathAbsInt(n int64) int64 {
	if n == math.MinInt64 {
		Panic("Int overflow; the result does not fit in signed 64 bits, so bound the operands or use BigInt")
	}
	if n < 0 {
		n = -n
	}
	return n
}

func StringTrim(text string) string              { return strings.TrimSpace(text) }
func StringUpper(text string) string             { return libraryUpper(text) }
func StringLower(text string) string             { return libraryLower(text) }
func StringContains(value, part string) bool     { return strings.Contains(value, part) }
func StringStartsWith(value, prefix string) bool { return strings.HasPrefix(value, prefix) }
func StringEndsWith(value, suffix string) bool   { return strings.HasSuffix(value, suffix) }
func StringLengthScalar(text string) int64       { return scalarCount(text) }
func StringIsEmpty(text string) bool             { return len(text) == 0 }
func StringCompare(left, right string) int64     { return int64(strings.Compare(left, right)) }
func StringConcat(left, right string) string     { return left + right }

// StringSplit and StringReplaceFirst are the calls that omit the optional cap;
// the library bodies share stringSplitLimit and stringReplaceLimit.
func StringSplit(text, separator string) Value {
	return stringSplitLimit(text, separator, nativeUnlimited)
}
func StringReplaceFirst(text, old, new string) string {
	return stringReplaceLimit(text, old, new, 1)
}
func StringJoin(parts Value, separator string) string {
	if list := parts.(*List); list.kind == listString {
		return strings.Join(list.strings, separator)
	}
	return strings.Join(libraryStringValues(parts), separator)
}

func stringSplitLimit(text, separator string, n int64) Value {
	if n < 0 {
		return Panic("split requires nonnegative max_parts; pass 0 or a positive count")
	}
	if n == 0 {
		return libraryStrings(nil)
	}
	if n > int64(len(text))+1 {
		n = int64(len(text)) + 1
	}
	parts := strings.Split(text, separator)
	if int64(len(parts)) > n {
		parts = parts[:n]
	}
	return &List{Type: "@std/List[String]", kind: listString, strings: parts}
}

func stringReplaceLimit(text, old, new string, n int64) string {
	if n < 0 {
		Panic("invalid replacement bounds")
	}
	bound := int64(len(text))
	if old == "" {
		bound = int64(utf8.RuneCountInString(text)) + 1
	}
	if n > bound {
		n = bound
	}
	return strings.Replace(text, old, new, int(n))
}

func StringToBytes(text string) Value { return Bytes{[]byte(text)} }

// StringParseInt parses signed ASCII decimal digits; anything else, including
// overflow, is none.
func StringParseInt(text string) Value {
	if text == "" {
		return optional("Int", nil, false)
	}
	start := 0
	if text[0] == '+' || text[0] == '-' {
		start = 1
	}
	if start == len(text) {
		return optional("Int", nil, false)
	}
	for i := start; i < len(text); i++ {
		if text[i] < '0' || text[i] > '9' {
			return optional("Int", nil, false)
		}
	}
	n, err := strconv.ParseInt(text, 10, 64)
	return optional("Int", n, err == nil)
}

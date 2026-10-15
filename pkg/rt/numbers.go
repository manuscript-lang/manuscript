package rt

import (
	"math"
	"math/big"
	"regexp"
	"strconv"
	"strings"
)

var numbersFloatSyntax = regexp.MustCompile(`^[+-]?[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?$`)

func numberFail[T any](e NumberError) Result[T, NumberError] { return Fail[T, NumberError](e) }

func Errors_Message_NumberError(_ *Execution, e NumberError) string {
	switch e.(type) {
	case NumberError_InvalidInput:
		return "number: " + txInvalidInput
	case NumberError_InvalidData:
		return "number: " + txInvalidData
	case NumberError_OutOfRange:
		return "number: " + txOutOfRange
	}
	return "number: operation failed"
}

func Numbers_ParseFloat(_ *Execution, text string) Result[float64, NumberError] {
	if !numbersFloatSyntax.MatchString(text) && text != "NaN" && text != "Infinity" && text != "-Infinity" {
		return numberFail[float64](NumberError_InvalidData{})
	}
	n, err := strconv.ParseFloat(text, 64)
	if err != nil {
		return numberFail[float64](NumberError_OutOfRange{})
	}
	return Ok[float64, NumberError](n)
}

func Numbers_ParseInt(_ *Execution, text string, radix int64) Result[int64, NumberError] {
	if radix < 2 || radix > 36 {
		return numberFail[int64](NumberError_InvalidInput{})
	}
	if !integerSyntax(text, int(radix)) {
		return numberFail[int64](NumberError_InvalidData{})
	}
	n, err := strconv.ParseInt(text, int(radix), 64)
	if err != nil {
		return numberFail[int64](NumberError_OutOfRange{})
	}
	return Ok[int64, NumberError](n)
}

// integerSyntax reports whether text is an optionally signed, nonempty run of
// digits valid in radix.
func integerSyntax(text string, radix int) bool {
	if text != "" && (text[0] == '+' || text[0] == '-') {
		text = text[1:]
	}
	if text == "" {
		return false
	}
	for _, r := range text {
		n := -1
		switch {
		case r >= '0' && r <= '9':
			n = int(r - '0')
		case r >= 'a' && r <= 'z':
			n = int(r-'a') + 10
		case r >= 'A' && r <= 'Z':
			n = int(r-'A') + 10
		}
		if n < 0 || n >= radix {
			return false
		}
	}
	return true
}

// Float and Int receiver operations.

func Float_ToString(_ *Execution, v float64) string { return FormatFloat(v) }
func Float_IsNan(_ *Execution, v float64) bool      { return math.IsNaN(v) }
func Float_IsFinite(_ *Execution, v float64) bool   { return !math.IsNaN(v) && !math.IsInf(v, 0) }

func Float_TruncateToInt(_ *Execution, v float64) Option[int64] {
	if math.IsNaN(v) || math.IsInf(v, 0) || v >= 9223372036854775808.0 || v < -9223372036854775808.0 {
		return None[int64]()
	}
	return Some(int64(v))
}

func formatPrecision(v float64, format byte, digits, minimum int64) Result[string, NumberError] {
	if digits < minimum || digits > 100 {
		return numberFail[string](NumberError_InvalidInput{})
	}
	return Ok[string, NumberError](formatFloatPrecision(v, format, int(digits)))
}

func Float_ToPrecision(_ *Execution, v float64, precision int64) Result[string, NumberError] {
	return formatPrecision(v, 'g', precision, 1)
}

func Float_ToExponential(_ *Execution, v float64, digits int64) Result[string, NumberError] {
	return formatPrecision(v, 'e', digits, 0)
}

func Float_ToFixed(_ *Execution, v float64, digits int64) Result[string, NumberError] {
	return formatPrecision(v, 'f', digits, 0)
}

// formatFloatPrecision preserves requested trailing digits. It uses binary64
// ties-to-even rounding and preserves signed zero.
func formatFloatPrecision(value float64, format byte, precision int) string {
	if math.IsNaN(value) || math.IsInf(value, 0) {
		return FormatFloat(value)
	}
	if format == 'f' {
		if math.Abs(value) >= 1e21 {
			return FormatFloat(value)
		}
		return strconv.FormatFloat(value, 'f', precision, 64)
	}
	digits := precision
	if format == 'g' {
		digits = precision - 1
	}
	mantissa, exponent, _ := strings.Cut(strconv.FormatFloat(value, 'e', digits, 64), "e")
	e, _ := strconv.Atoi(exponent)
	if format == 'g' && e >= -6 && e < precision {
		return strconv.FormatFloat(value, 'f', precision-e-1, 64)
	}
	sign := "+"
	if e < 0 {
		sign = ""
	}
	return mantissa + "e" + sign + strconv.Itoa(e)
}

func durationOf(operation string, n, scale int64) Duration {
	if n < math.MinInt64/scale || n > math.MaxInt64/scale {
		txRangeFault(operation, "value", n, math.MinInt64/scale, math.MaxInt64/scale)
	}
	return Duration(n * scale)
}

func Int_Milliseconds(_ *Execution, n int64) Duration {
	return durationOf("Int.milliseconds", n, 1_000_000)
}
func Int_Seconds(_ *Execution, n int64) Duration { return durationOf("Int.seconds", n, 1_000_000_000) }
func Int_Minutes(_ *Execution, n int64) Duration { return durationOf("Int.minutes", n, 60_000_000_000) }

func Int_ToString(_ *Execution, v, radix int64) string {
	if radix < 2 || radix > 36 {
		txRangeFault("Int.to_string", "radix", radix, 2, 36)
	}
	return strconv.FormatInt(v, int(radix))
}

func Int_ToFloat(_ *Execution, v int64) float64 { return float64(v) }

func Int_ToDecimal(_ *Execution, v int64) *Decimal {
	return &Decimal{Value: new(big.Rat).SetInt64(v)}
}

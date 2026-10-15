package rt

import (
	"math"
	"strconv"
	"strings"
	"testing"

	"github.com/manuscript-lang/manuscript/internal/decimal"
)

// faultMessage runs f and returns the message of the fault it raised, or "".
func faultMessage(f func()) (message string) {
	defer func() {
		if r := recover(); r != nil {
			if fault, ok := r.(Fault); ok {
				message = fault.Message
				return
			}
			panic(r)
		}
	}()
	f()
	return ""
}

func decimalModeOf(tag string) Option[RoundingMode] {
	switch tag {
	case "HalfEven":
		return Some[RoundingMode](RoundingMode_HalfEven{})
	case "HalfAwayFromZero":
		return Some[RoundingMode](RoundingMode_HalfAwayFromZero{})
	case "TowardZero":
		return Some[RoundingMode](RoundingMode_TowardZero{})
	case "Floor":
		return Some[RoundingMode](RoundingMode_Floor{})
	case "Ceil":
		return Some[RoundingMode](RoundingMode_Ceil{})
	}
	return None[RoundingMode]()
}

func TestDecimalRoundingModes(t *testing.T) {
	ctx := RootExecution()
	inputs := []string{"2.4d", "2.5d", "2.6d", "3.5d", "-2.4d", "-2.5d", "-2.6d", "-3.5d", "0d"}
	for mode, wants := range map[string][]string{
		"HalfEven":         {"2", "2", "3", "4", "-2", "-2", "-3", "-4", "0"},
		"HalfAwayFromZero": {"2", "3", "3", "4", "-2", "-3", "-3", "-4", "0"},
		"TowardZero":       {"2", "2", "2", "3", "-2", "-2", "-2", "-3", "0"},
		"Floor":            {"2", "2", "2", "3", "-3", "-3", "-3", "-4", "0"},
		"Ceil":             {"3", "3", "3", "4", "-2", "-2", "-2", "-3", "0"},
	} {
		for i, input := range inputs {
			d := DecimalLiteral(input)
			before := d.String()
			rounded := Decimal_Round(ctx, d, 0, decimalModeOf(mode))
			fixed := Decimal_ToFixed(ctx, d, 0, decimalModeOf(mode))
			if rounded.Failed || fixed.Failed || rounded.Val.String() != wants[i] || fixed.Val != wants[i] {
				t.Errorf("%s %s: round %v, fixed %v, want %s", mode, input, rounded, fixed, wants[i])
			}
			if d.String() != before {
				t.Fatal("rounding mutated its receiver")
			}
		}
	}
}

func TestDecimalDefaultModeIsHalfEven(t *testing.T) {
	ctx := RootExecution()
	if got := Decimal_ToFixed(ctx, DecimalLiteral("2.5d"), 0, None[RoundingMode]()); got.Val != "2" {
		t.Fatalf("default mode: %v", got)
	}
}

func TestDecimalScaleAndPrecision(t *testing.T) {
	ctx := RootExecution()
	for _, tt := range []struct {
		input, mode, want string
		places            int64
	}{
		{"4.947525d", "HalfEven", "4.95d", 2},
		{"1.245d", "HalfEven", "1.24d", 2},
		{"1.255d", "HalfEven", "1.26d", 2},
		{"-1.245d", "HalfEven", "-1.24d", 2},
		{"1.245000000000000000000000000000001d", "HalfEven", "1.25d", 2},
		{"1.244999999999999999999999999999999d", "HalfEven", "1.24d", 2},
		{"12345678901234567890123456789012.55d", "HalfEven", "12345678901234567890123456789012.6d", 1},
		{"1250d", "HalfEven", "1200d", -2},
		{"1350d", "HalfEven", "1400d", -2},
		{"-1250d", "HalfAwayFromZero", "-1300d", -2},
		{"-1251d", "Floor", "-1300d", -2},
		{"1251d", "Ceil", "1300d", -2},
		{"1e-6176d", "HalfEven", "1e-6176d", 6176},
		{"1e-6176d", "HalfEven", "0d", 6175},
		{"5e-6176d", "HalfEven", "0d", 6175},
		{"5e-6176d", "HalfAwayFromZero", "1e-6175d", 6175},
		{"-5e-6176d", "Floor", "-1e-6175d", 6175},
		{"1e6144d", "HalfEven", "1e6144d", -6144},
		{"5e6143d", "HalfEven", "0d", -6144},
		{"5e6143d", "HalfAwayFromZero", "1e6144d", -6144},
		{"9.999999999999999999999999999999999e6144d", "Floor", "9e6144d", -6144},
		{"9.999999999999999999999999999999999e6144d", "HalfEven", "1e6145d", -6144},
		{"9.999999999999999999999999999999999e6144d", "HalfEven", "9.999999999999999999999999999999999e6144d", 6176},
		{"0d", "Ceil", "0d", -6144},
		{"0d", "Floor", "0d", 6176},
	} {
		result := Decimal_Round(ctx, DecimalLiteral(tt.input), tt.places, decimalModeOf(tt.mode))
		if !decimal.Valid(tt.want) {
			if _, out := result.Err.(NumberError_OutOfRange); !result.Failed || !out {
				t.Errorf("%s/%s/%d: want OutOfRange, got %v", tt.input, tt.mode, tt.places, result)
			}
			continue
		}
		if result.Failed || result.Val.Value.Cmp(DecimalLiteral(tt.want).Value) != 0 {
			t.Errorf("%s/%s/%d: got %v, want %s", tt.input, tt.mode, tt.places, result, tt.want)
		}
	}
}

func TestDecimalFixedPlaces(t *testing.T) {
	ctx := RootExecution()
	for _, tt := range []struct {
		input, want string
		digits      int64
	}{
		{"25.50d", "25.50", 2}, {"1d", "1.0000", 4}, {"0d", "0.00", 2},
		{"-0.005d", "0.00", 2}, {"-0.006d", "-0.01", 2}, {"9.995d", "10.00", 2},
		{"-9.995d", "-10.00", 2}, {"9007199254740993.125d", "9007199254740993.12", 2},
		{"12345678901234567890123456789012.55d", "12345678901234567890123456789012.6", 1},
		{"1e21d", "1000000000000000000000.00", 2}, {"1e-7d", "0.00000010", 8},
		{"1e6144d", "1" + strings.Repeat("0", 6144) + ".00", 2},
		{"1e-6176d", "0." + strings.Repeat("0", 6175) + "1", 6176},
		{"0d", "0." + strings.Repeat("0", 6176), 6176},
		{"9.999999999999999999999999999999999e6144d", strings.Repeat("9", 34) + strings.Repeat("0", 6111) + "." + strings.Repeat("0", 6176), 6176},
	} {
		got := Decimal_ToFixed(ctx, DecimalLiteral(tt.input), tt.digits, decimalModeOf("HalfEven"))
		if got.Failed || got.Val != tt.want {
			t.Errorf("%s to_fixed(%d): unexpected output (%d bytes), want %d bytes", tt.input, tt.digits, len(got.Val), len(tt.want))
		}
	}
}

func TestDecimalInvalidRequests(t *testing.T) {
	ctx := RootExecution()
	zero := DecimalLiteral("0d")
	for _, places := range []int64{math.MinInt64, -6145, 6177, math.MaxInt64} {
		if r := Decimal_Round(ctx, zero, places, decimalModeOf("HalfEven")); !r.Failed {
			t.Errorf("round(%d) succeeded", places)
		}
	}
	for _, digits := range []int64{math.MinInt64, -1, 6177, math.MaxInt64} {
		if r := Decimal_ToFixed(ctx, zero, digits, decimalModeOf("HalfEven")); !r.Failed {
			t.Errorf("to_fixed(%d) succeeded", digits)
		}
	}
}

func TestDecimalArithmeticAndFormatting(t *testing.T) {
	a, b := DecimalLiteral("0.1d"), DecimalLiteral("0.2d")
	if got := DecimalAdd(a, b); got.String() != "0.3" || !got.Equal(tctx, DecimalLiteral("0.3d")) {
		t.Fatalf("0.1 + 0.2 = %s", got)
	}
	if got := DecimalDivide(DecimalLiteral("1d"), DecimalLiteral("3d")).String(); got != "0.3333333333333333333333333333333333" {
		t.Fatalf("1/3 = %s", got)
	}
	if got := DecimalNegate(DecimalLiteral("0d")).String(); got != "0" {
		t.Fatalf("-0 = %s", got)
	}
	if !DecimalLess(a, b) || DecimalGreater(a, b) || !DecimalLessEqual(a, a) || !DecimalGreaterEqual(b, a) {
		t.Fatal("ordering")
	}
	if got := faultMessage(func() { DecimalDivide(a, DecimalLiteral("0d")) }); got != "Decimal./: division by zero; right must be nonzero, found 0" {
		t.Fatalf("division fault: %q", got)
	}
	huge := DecimalLiteral("9e6144d")
	got := faultMessage(func() { DecimalMultiply(huge, DecimalLiteral("10d")) })
	if !strings.HasPrefix(got, "Decimal.*: overflow; found left 9e+6144 and right 10;") {
		t.Fatalf("overflow fault: %q", got)
	}
}

func TestDecimalConversions(t *testing.T) {
	ctx := RootExecution()
	if got := Int_ToDecimal(ctx, math.MinInt64).String(); got != strconv.FormatInt(math.MinInt64, 10) {
		t.Fatalf("int to decimal: %s", got)
	}
	if got := Decimal_ToFloat(ctx, DecimalLiteral("0.5d")); got != 0.5 {
		t.Fatalf("to_float: %v", got)
	}
	if got := Decimal_ToFloat(ctx, DecimalLiteral("1e6000d")); !math.IsInf(got, 1) {
		t.Fatalf("overflowing to_float: %v", got)
	}
	for text, want := range map[string]Option[int64]{
		"-2.9d": Some(int64(-2)), "2.9d": Some(int64(2)), "9223372036854775807d": Some(int64(math.MaxInt64)),
		"9223372036854775808d": None[int64](),
	} {
		if got := Decimal_TruncateToInt(ctx, DecimalLiteral(text)); got != want {
			t.Errorf("truncate %s: %v want %v", text, got, want)
		}
	}
	if got := faultMessage(func() { DecimalLiteral("0.1234567890123456789012345678901234567d") }); got != "invalid or inexact Decimal literal" {
		t.Fatalf("inexact literal: %q", got)
	}
}

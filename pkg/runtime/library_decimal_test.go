package msruntime

import (
	"math"
	"math/big"
	"strings"
	"testing"
)

func decimalMode(tag string) Alternative { return Alternative{Type: "@std/RoundingMode", Tag: tag} }

func TestDecimalRoundingModes(t *testing.T) {
	inputs := []string{"2.4d", "2.5d", "2.6d", "3.5d", "-2.4d", "-2.5d", "-2.6d", "-3.5d", "0d"}
	for mode, wants := range map[string][]string{
		"HalfEven":         {"2", "2", "3", "4", "-2", "-2", "-3", "-4", "0"},
		"HalfAwayFromZero": {"2", "3", "3", "4", "-2", "-3", "-3", "-4", "0"},
		"TowardZero":       {"2", "2", "2", "3", "-2", "-2", "-2", "-3", "0"},
		"Floor":            {"2", "2", "2", "3", "-3", "-3", "-3", "-4", "0"},
		"Ceil":             {"3", "3", "3", "4", "-2", "-2", "-2", "-3", "0"},
	} {
		t.Run(mode, func(t *testing.T) {
			for i, input := range inputs {
				d := DecimalLiteral(input).(Decimal)
				before := new(big.Rat).Set(d.Value)
				rounded := librarySuccess(t, libraryCall(t, "decimal/round", d, int64(0), decimalMode(mode)))
				fixed := librarySuccess(t, libraryCall(t, "decimal/to_fixed", d, int64(0), decimalMode(mode)))
				if Format(rounded) != wants[i] || fixed != wants[i] {
					t.Errorf("%s: round %s, fixed %s, want %s", input, Format(rounded), fixed, wants[i])
				}
				if d.Value.Cmp(before) != 0 {
					t.Fatal("rounding mutated its receiver")
				}
			}
		})
	}
}

func TestDecimalScaleAndPrecision(t *testing.T) {
	for _, tt := range []struct {
		input, mode, want string
		places            int64
	}{
		{"4.947525d", "HalfEven", "4.95d", 2},
		{"64.917525d", "HalfEven", "64.92d", 2},
		{"1.245d", "HalfEven", "1.24d", 2},
		{"1.255d", "HalfEven", "1.26d", 2},
		{"-1.245d", "HalfEven", "-1.24d", 2},
		{"-1.255d", "HalfEven", "-1.26d", 2},
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
		t.Run(tt.input+"/"+tt.mode+"/"+Format(tt.places), func(t *testing.T) {
			result := libraryCall(t, "decimal/round", DecimalLiteral(tt.input), tt.places, decimalMode(tt.mode))
			if !ValidateDecimalLiteral(tt.want) {
				libraryFailure(t, result, "OutOfRange")
				return
			}
			if got := librarySuccess(t, result).(Decimal); got.Value.Cmp(DecimalLiteral(tt.want).(Decimal).Value) != 0 {
				t.Errorf("got %s, want %s", got, tt.want)
			}
		})
	}
}

func TestDecimalFixedPlaces(t *testing.T) {
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
		if got := librarySuccess(t, libraryCall(t, "decimal/to_fixed", DecimalLiteral(tt.input), tt.digits, decimalMode("HalfEven"))); got != tt.want {
			t.Errorf("%s to_fixed(%d): unexpected output (%d bytes), want %d bytes", tt.input, tt.digits, len(got.(string)), len(tt.want))
		}
	}
}

func TestDecimalInvalidRequests(t *testing.T) {
	for name, places := range map[string][]int64{
		"round":    {math.MinInt64, -6145, 6177, math.MaxInt64},
		"to_fixed": {math.MinInt64, -1, 6177, math.MaxInt64},
	} {
		for _, places := range places {
			libraryFailure(t, libraryCall(t, "decimal/"+name, DecimalLiteral("0d"), places, decimalMode("HalfEven")), "InvalidInput")
		}
		libraryFailure(t, libraryCall(t, "decimal/"+name, DecimalLiteral("0d"), int64(0), decimalMode("Unknown")), "InvalidInput")
	}
}

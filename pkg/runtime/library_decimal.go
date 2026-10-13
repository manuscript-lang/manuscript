package msruntime

import (
	"math/big"
	"strconv"
	"strings"
)

func init() {
	p := func(name, typ string) LibraryParam { return LibraryParam{name, typ} }
	libraryAdd("decimal", "round", libraryResult("Decimal", "NumberError"), []LibraryParam{p("value", "Decimal"), p("places", "Int"), p("mode", "Optional[RoundingMode]")}, func(_ *Execution, result string, args []Value) Value {
		places := nativeInteger(args[1])
		if places < -6144 || places > 6176 {
			return libraryError(result, "InvalidInput", "")
		}
		coefficient, valid := decimalRoundedCoefficient(args[0].(Decimal), int(places), decimalRoundingMode(args[2]))
		if !valid {
			return libraryError(result, "InvalidInput", "")
		}
		// Check exact representability rather than applying the arithmetic context,
		// which would introduce a second rounding step.
		value := coefficient.String() + "e" + strconv.FormatInt(-places, 10)
		if !ValidateDecimalLiteral(value) {
			return libraryError(result, "OutOfRange", "")
		}
		return libraryOK(result, DecimalLiteral(value))
	})
	libraryAdd("decimal", "to_fixed", libraryResult("String", "NumberError"), []LibraryParam{p("value", "Decimal"), p("digits", "Int"), p("mode", "Optional[RoundingMode]")}, func(_ *Execution, result string, args []Value) Value {
		digits := nativeInteger(args[1])
		if digits < 0 || digits > 6176 {
			return libraryError(result, "InvalidInput", "")
		}
		coefficient, valid := decimalRoundedCoefficient(args[0].(Decimal), int(digits), decimalRoundingMode(args[2]))
		if !valid {
			return libraryError(result, "InvalidInput", "")
		}
		negative := coefficient.Sign() < 0
		text := new(big.Int).Abs(coefficient).String()
		if digits > 0 {
			if len(text) <= int(digits) {
				text = strings.Repeat("0", int(digits)+1-len(text)) + text
			}
			point := len(text) - int(digits)
			text = text[:point] + "." + text[point:]
		}
		if negative {
			text = "-" + text
		}
		return libraryOK(result, text)
	})
}

// decimalRoundedCoefficient rounds the exact scaled value once. Callers validate
// places before allocating powers of ten; the receiver's rational is never mutated.
func decimalRoundedCoefficient(value Decimal, places int, mode string) (*big.Int, bool) {
	switch mode {
	case "HalfEven", "HalfAwayFromZero", "TowardZero", "Floor", "Ceil":
	default:
		return nil, false
	}
	scaled := new(big.Rat).Abs(value.Value)
	exponent := places
	if exponent < 0 {
		exponent = -exponent
	}
	scale := new(big.Rat).SetInt(pow10(exponent))
	if places >= 0 {
		scaled.Mul(scaled, scale)
	} else {
		scaled.Quo(scaled, scale)
	}
	coefficient, remainder := new(big.Int), new(big.Int)
	coefficient.QuoRem(scaled.Num(), scaled.Denom(), remainder)
	if remainder.Sign() != 0 {
		increment := false
		switch mode {
		case "HalfEven", "HalfAwayFromZero":
			cmp := new(big.Int).Lsh(remainder, 1).Cmp(scaled.Denom())
			increment = cmp > 0 || cmp == 0 && (mode == "HalfAwayFromZero" || coefficient.Bit(0) == 1)
		case "Floor":
			increment = value.Value.Sign() < 0
		case "Ceil":
			increment = value.Value.Sign() > 0
		}
		if increment {
			coefficient.Add(coefficient, big.NewInt(1))
		}
	}
	if value.Value.Sign() < 0 {
		coefficient.Neg(coefficient)
	}
	return coefficient, true
}

func decimalRoundingMode(value Value) string {
	mode, _ := nativeOption(value, "RoundingMode", Alternative{Type: "@std/RoundingMode", Tag: "HalfEven"})
	return mode.(Alternative).Tag
}

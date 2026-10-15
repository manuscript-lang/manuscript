package msruntime

import (
	"fmt"
	"math/big"
	"strconv"
	"strings"

	"github.com/manuscript-lang/manuscript/internal/decimal"
)

// Decimal is an immutable exact decimal value of at most 34 significant
// digits. Value is never modified after construction.
type Decimal struct{ Value *big.Rat }

// DecimalLiteral builds the Decimal of a source literal the checker accepted.
func DecimalLiteral(text string) *Decimal {
	coefficient, exponent, negative, valid := decimal.Parts(text)
	if !valid {
		Raise("invalid or inexact Decimal literal")
	}
	if coefficient == "0" {
		return &Decimal{new(big.Rat)}
	}
	if negative {
		coefficient = "-" + coefficient
	}
	value, ok := new(big.Rat).SetString(coefficient + "e" + strconv.Itoa(exponent))
	if !ok {
		Raise("invalid Decimal literal")
	}
	return &Decimal{value}
}

// String formats with at most 34 significant digits, as interpolation does.
func (d *Decimal) String() string {
	if d.Value.Sign() == 0 {
		return "0"
	}
	e := decimalExponent(d.Value)
	scaled := decimalScaled(new(big.Rat).Abs(d.Value), e-33)
	return renderDecimal(scaled.Num().String(), e, d.Value.Sign() < 0)
}

// FormatDecimal is the interpolation text of a Decimal.
func FormatDecimal(d *Decimal) string { return d.String() }

// Equal compares exactly.
func (d *Decimal) Equal(_ *Execution, other *Decimal) bool { return d.Value.Cmp(other.Value) == 0 }

func decimalPow10(n int) *big.Int { return new(big.Int).Exp(big.NewInt(10), big.NewInt(int64(n)), nil) }

// decimalScaled returns r / 10^q.
func decimalScaled(r *big.Rat, q int) *big.Rat {
	out := new(big.Rat).Set(r)
	if q >= 0 {
		return out.Quo(out, new(big.Rat).SetInt(decimalPow10(q)))
	}
	return out.Mul(out, new(big.Rat).SetInt(decimalPow10(-q)))
}

func decimalExponent(r *big.Rat) int {
	if r.Sign() == 0 {
		return 0
	}
	n := new(big.Int).Abs(r.Num())
	d := r.Denom()
	e := len(n.String()) - len(d.String())
	if e >= 0 {
		if n.Cmp(new(big.Int).Mul(d, decimalPow10(e))) < 0 {
			e--
		}
	} else if new(big.Int).Mul(n, decimalPow10(-e)).Cmp(d) < 0 {
		e--
	}
	return e
}

// decimalRound34 rounds r half-even to 34 significant digits and faults when
// the magnitude exceeds the format.
func decimalRound34(r *big.Rat, operation string, left, right *Decimal) *Decimal {
	if r.Sign() == 0 {
		return &Decimal{new(big.Rat)}
	}
	q := max(decimalExponent(r)-33, -6176)
	scaled := decimalScaled(new(big.Rat).Abs(r), q)
	coefficient, remainder := new(big.Int), new(big.Int)
	coefficient.QuoRem(scaled.Num(), scaled.Denom(), remainder)
	cmp := new(big.Int).Lsh(remainder, 1).Cmp(scaled.Denom())
	if cmp > 0 || cmp == 0 && coefficient.Bit(0) == 1 {
		coefficient.Add(coefficient, big.NewInt(1))
	}
	if r.Sign() < 0 {
		coefficient.Neg(coefficient)
	}
	out := new(big.Rat).SetInt(coefficient)
	if q >= 0 {
		out.Mul(out, new(big.Rat).SetInt(decimalPow10(q)))
	} else {
		out.Quo(out, new(big.Rat).SetInt(decimalPow10(-q)))
	}
	if out.Sign() != 0 && decimalExponent(out) > 6144 {
		Raise(fmt.Sprintf("Decimal.%s: overflow; found left %s and right %s; rounded magnitude must be at most 9.999999999999999999999999999999999e6144 (34 significant digits)", operation, left.String(), right.String()))
	}
	return &Decimal{out}
}

// Operators. The lowerer calls these for Decimal operands.

func DecimalAdd(a, b *Decimal) *Decimal {
	return decimalRound34(new(big.Rat).Add(a.Value, b.Value), "+", a, b)
}

func DecimalSubtract(a, b *Decimal) *Decimal {
	return decimalRound34(new(big.Rat).Sub(a.Value, b.Value), "-", a, b)
}

func DecimalMultiply(a, b *Decimal) *Decimal {
	return decimalRound34(new(big.Rat).Mul(a.Value, b.Value), "*", a, b)
}

func DecimalDivide(a, b *Decimal) *Decimal {
	if b.Value.Sign() == 0 {
		Raise("Decimal./: division by zero; right must be nonzero, found 0")
	}
	return decimalRound34(new(big.Rat).Quo(a.Value, b.Value), "/", a, b)
}

func DecimalNegate(a *Decimal) *Decimal { return &Decimal{new(big.Rat).Neg(a.Value)} }

func DecimalLess(a, b *Decimal) bool         { return a.Value.Cmp(b.Value) < 0 }
func DecimalLessEqual(a, b *Decimal) bool    { return a.Value.Cmp(b.Value) <= 0 }
func DecimalGreater(a, b *Decimal) bool      { return a.Value.Cmp(b.Value) > 0 }
func DecimalGreaterEqual(a, b *Decimal) bool { return a.Value.Cmp(b.Value) >= 0 }

func Decimal_ToFloat(_ *Execution, d *Decimal) float64 {
	f, _ := d.Value.Float64()
	return f
}

// Decimal_TruncateToInt discards the fraction toward zero.
func Decimal_TruncateToInt(_ *Execution, d *Decimal) Option[int64] {
	q := new(big.Int).Quo(d.Value.Num(), d.Value.Denom())
	if !q.IsInt64() {
		return None[int64]()
	}
	return Some(q.Int64())
}

// decimalRoundedCoefficient rounds the exact scaled value once. Callers
// validate places before allocating powers of ten.
func decimalRoundedCoefficient(value *Decimal, places int, mode RoundingMode) (*big.Int, bool) {
	var halfEven, halfAway, floor, ceil bool
	switch mode.(type) {
	case nil, RoundingMode_HalfEven:
		halfEven = true
	case RoundingMode_HalfAwayFromZero:
		halfAway = true
	case RoundingMode_TowardZero:
	case RoundingMode_Floor:
		floor = true
	case RoundingMode_Ceil:
		ceil = true
	default:
		return nil, false
	}
	scaled := decimalScaled(new(big.Rat).Abs(value.Value), -places)
	coefficient, remainder := new(big.Int), new(big.Int)
	coefficient.QuoRem(scaled.Num(), scaled.Denom(), remainder)
	if remainder.Sign() != 0 {
		increment := false
		switch {
		case halfEven || halfAway:
			cmp := new(big.Int).Lsh(remainder, 1).Cmp(scaled.Denom())
			increment = cmp > 0 || cmp == 0 && (halfAway || coefficient.Bit(0) == 1)
		case floor:
			increment = value.Value.Sign() < 0
		case ceil:
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

func decimalMode(o Option[RoundingMode]) RoundingMode {
	if !o.Some {
		return RoundingMode_HalfEven{}
	}
	return o.Val
}

func Decimal_Round(_ *Execution, d *Decimal, places int64, mode Option[RoundingMode]) Result[*Decimal, NumberError] {
	if places < -6144 || places > 6176 {
		return numberFail[*Decimal](NumberError_InvalidInput{})
	}
	coefficient, valid := decimalRoundedCoefficient(d, int(places), decimalMode(mode))
	if !valid {
		return numberFail[*Decimal](NumberError_InvalidInput{})
	}
	// Check exact representability rather than applying the arithmetic
	// context, which would introduce a second rounding step.
	text := coefficient.String() + "e" + strconv.FormatInt(-places, 10)
	if !decimal.Valid(text) {
		return numberFail[*Decimal](NumberError_OutOfRange{})
	}
	return Ok[*Decimal, NumberError](DecimalLiteral(text))
}

func Decimal_ToFixed(_ *Execution, d *Decimal, digits int64, mode Option[RoundingMode]) Result[string, NumberError] {
	if digits < 0 || digits > 6176 {
		return numberFail[string](NumberError_InvalidInput{})
	}
	coefficient, valid := decimalRoundedCoefficient(d, int(digits), decimalMode(mode))
	if !valid {
		return numberFail[string](NumberError_InvalidInput{})
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
	return Ok[string, NumberError](text)
}

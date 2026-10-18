package msruntime

import (
	"fmt"
	"math/big"
	"strconv"
	"strings"
	"sync/atomic"

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
	n, ok := new(big.Int).SetString(coefficient, 10)
	if !ok {
		Raise("invalid Decimal literal")
	}
	value := new(big.Rat).SetInt(n)
	if exponent > 0 {
		value.SetInt(n.Mul(n, decimalPow10(exponent)))
	} else if exponent < 0 {
		value.SetFrac(n, decimalPow10(-exponent))
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

// decimalPow10Cache holds the powers of ten a Decimal can need (up to the
// format's largest scale), built on first use. Callers must treat the result
// as read-only.
var decimalPow10Cache [6400]atomic.Pointer[big.Int]

func decimalPow10(n int) *big.Int {
	if n < 0 || n >= len(decimalPow10Cache) {
		return new(big.Int).Exp(big.NewInt(10), big.NewInt(int64(n)), nil)
	}
	if p := decimalPow10Cache[n].Load(); p != nil {
		return p
	}
	p := new(big.Int).Exp(big.NewInt(10), big.NewInt(int64(n)), nil)
	decimalPow10Cache[n].Store(p)
	return p
}

// decimalDigits is the number of decimal digits of a positive integer.
func decimalDigits(n *big.Int) int {
	if n.IsInt64() {
		return len(strconv.FormatInt(n.Int64(), 10))
	}
	// 2^(bits-1) <= n < 2^bits, so the digit count is estimate or estimate+1.
	estimate := int(float64(n.BitLen()-1)*0.30102999566398120) + 1
	if n.Cmp(decimalPow10(estimate)) >= 0 {
		estimate++
	}
	return estimate
}

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
	e := decimalDigits(n) - decimalDigits(d)
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
	exponent := decimalExponent(r)
	q := max(exponent-33, -6176)
	if decimalScalesExactly(r, q) {
		// The value already has at most 34 significant digits: nothing to round.
		if exponent > 6144 {
			decimalOverflow(operation, left, right)
		}
		return &Decimal{r}
	}
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
		decimalOverflow(operation, left, right)
	}
	return &Decimal{out}
}

func decimalOverflow(operation string, left, right *Decimal) {
	Raise(fmt.Sprintf("Decimal.%s: overflow; found left %s and right %s; rounded magnitude must be at most 9.999999999999999999999999999999999e6144 (34 significant digits)", operation, left.String(), right.String()))
}

// decimalScalesExactly reports whether r / 10^q is an integer, so rounding to
// that quantum changes nothing.
func decimalScalesExactly(r *big.Rat, q int) bool {
	num, denom := r.Num(), r.Denom()
	if q >= 0 {
		return denom.IsInt64() && denom.Int64() == 1 && new(big.Int).Rem(num, decimalPow10(q)).Sign() == 0
	}
	return new(big.Int).Rem(decimalPow10(-q), denom).Sign() == 0
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
func Decimal_TruncateToInt(_ *Execution, d *Decimal) Option[int] {
	q := new(big.Int).Quo(d.Value.Num(), d.Value.Denom())
	return bigToInt(q)
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
	// |value| * 10^places as numerator over denominator, left unreduced: the
	// quotient, and the remainder's ratio to the denominator, are the same.
	numerator, denominator := new(big.Int).Abs(value.Value.Num()), value.Value.Denom()
	if places >= 0 {
		numerator.Mul(numerator, decimalPow10(places))
	} else {
		denominator = new(big.Int).Mul(denominator, decimalPow10(-places))
	}
	coefficient, remainder := new(big.Int), new(big.Int)
	coefficient.QuoRem(numerator, denominator, remainder)
	if remainder.Sign() != 0 {
		increment := false
		switch {
		case halfEven || halfAway:
			cmp := new(big.Int).Lsh(remainder, 1).Cmp(denominator)
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

func Decimal_Round(_ *Execution, d *Decimal, places int, mode Option[RoundingMode]) Result[*Decimal, NumberError] {
	if places < -6144 || places > 6176 {
		return numberFail[*Decimal](NumberError_InvalidInput{})
	}
	coefficient, valid := decimalRoundedCoefficient(d, int(places), decimalMode(mode))
	if !valid {
		return numberFail[*Decimal](NumberError_InvalidInput{})
	}
	// Check exact representability rather than applying the arithmetic
	// context, which would introduce a second rounding step.
	text := coefficient.String() + "e" + strconv.Itoa(-places)
	if !decimal.Valid(text) {
		return numberFail[*Decimal](NumberError_OutOfRange{})
	}
	return Ok[*Decimal, NumberError](DecimalLiteral(text))
}

func Decimal_ToFixed(_ *Execution, d *Decimal, digits int, mode Option[RoundingMode]) Result[string, NumberError] {
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

func Decimal_Compare(_ *Execution, a, b *Decimal) int { return a.Value.Cmp(b.Value) }

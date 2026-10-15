package msruntime

import (
	"math/big"
	"strings"
)

// BigInt is an immutable arbitrary-precision integer. The wrapped value is
// never modified after construction.
type BigInt struct{ n *big.Int }

// String is the base-10 text of the value.
func (b *BigInt) String() string { return b.n.String() }

// Equal reports whether two BigInts hold the same integer.
func (b *BigInt) Equal(_ *Execution, other *BigInt) bool { return b.n.Cmp(other.n) == 0 }

func bigFail[T any](e BigIntError) Result[T, BigIntError] { return Fail[T, BigIntError](e) }

func Errors_Message_BigIntError(_ *Execution, e BigIntError) string {
	switch e.(type) {
	case BigIntError_InvalidInput:
		return "big integer: " + txInvalidInput
	case BigIntError_InvalidData:
		return "big integer: " + txInvalidData
	case BigIntError_LimitExceeded:
		return "big integer: " + txLimitExceeded
	}
	return "big integer: operation failed"
}

func Bigint_FromInt(_ *Execution, v int64) *BigInt { return &BigInt{big.NewInt(v)} }

func Bigint_Parse(_ *Execution, text string, radix int64, maxDigits Option[int64]) Result[*BigInt, BigIntError] {
	n := txLimit(maxDigits)
	if radix < 2 || radix > 36 || n < 0 {
		return bigFail[*BigInt](BigIntError_InvalidInput{})
	}
	digits := len(strings.TrimPrefix(strings.TrimPrefix(text, "+"), "-"))
	if int64(digits) > n {
		return bigFail[*BigInt](BigIntError_LimitExceeded{})
	}
	if !integerSyntax(text, int(radix)) {
		return bigFail[*BigInt](BigIntError_InvalidData{})
	}
	v, ok := new(big.Int).SetString(text, int(radix))
	if !ok {
		return bigFail[*BigInt](BigIntError_InvalidData{})
	}
	return Ok[*BigInt, BigIntError](&BigInt{v})
}

func BigInt_Add(_ *Execution, a, b *BigInt) *BigInt      { return &BigInt{new(big.Int).Add(a.n, b.n)} }
func BigInt_Subtract(_ *Execution, a, b *BigInt) *BigInt { return &BigInt{new(big.Int).Sub(a.n, b.n)} }
func BigInt_Multiply(_ *Execution, a, b *BigInt) *BigInt { return &BigInt{new(big.Int).Mul(a.n, b.n)} }
func BigInt_BitAnd(_ *Execution, a, b *BigInt) *BigInt   { return &BigInt{new(big.Int).And(a.n, b.n)} }
func BigInt_BitOr(_ *Execution, a, b *BigInt) *BigInt    { return &BigInt{new(big.Int).Or(a.n, b.n)} }
func BigInt_BitXor(_ *Execution, a, b *BigInt) *BigInt   { return &BigInt{new(big.Int).Xor(a.n, b.n)} }

// BigInt_Divide truncates toward zero.
func BigInt_Divide(_ *Execution, a, b *BigInt) Result[*BigInt, BigIntError] {
	if b.n.Sign() == 0 {
		return bigFail[*BigInt](BigIntError_InvalidInput{})
	}
	return Ok[*BigInt, BigIntError](&BigInt{new(big.Int).Quo(a.n, b.n)})
}

// BigInt_Remainder takes the sign of the dividend.
func BigInt_Remainder(_ *Execution, a, b *BigInt) Result[*BigInt, BigIntError] {
	if b.n.Sign() == 0 {
		return bigFail[*BigInt](BigIntError_InvalidInput{})
	}
	return Ok[*BigInt, BigIntError](&BigInt{new(big.Int).Rem(a.n, b.n)})
}

func BigInt_Compare(_ *Execution, a, b *BigInt) int64 { return int64(a.n.Cmp(b.n)) }

func BigInt_ToInt(_ *Execution, v *BigInt) Option[int64] {
	if !v.n.IsInt64() {
		return None[int64]()
	}
	return Some(v.n.Int64())
}

func BigInt_ToString(_ *Execution, v *BigInt, radix int64) string {
	if radix < 2 || radix > 36 {
		txRangeFault("BigInt.to_string", "radix", radix, 2, 36)
	}
	return v.n.Text(int(radix))
}

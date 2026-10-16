package msruntime

import (
	"math/big"
	"math/rand"
	"testing"
)

// decimalRound34Reference is the unoptimized rounding the fast paths must match.
func decimalRound34Reference(r *big.Rat) *big.Rat {
	if r.Sign() == 0 {
		return new(big.Rat)
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
	return out
}

func TestDecimalRound34MatchesReference(t *testing.T) {
	rng := rand.New(rand.NewSource(1))
	randInt := func() *big.Int {
		digits := rng.Intn(60) + 1
		n := new(big.Int).Rand(rng, decimalPow10(digits))
		if rng.Intn(2) == 0 {
			n.Neg(n)
		}
		return n
	}
	for i := 0; i < 5000; i++ {
		num := randInt()
		var denom *big.Int
		switch rng.Intn(3) {
		case 0:
			denom = decimalPow10(rng.Intn(40))
		case 1:
			denom = big.NewInt(int64(rng.Intn(1000) + 1))
		default:
			denom = new(big.Int).Add(randInt().Abs(randInt()), big.NewInt(1))
		}
		r := new(big.Rat).SetFrac(num, denom)
		want := decimalRound34Reference(r)
		got := decimalRound34(new(big.Rat).Set(r), "+", &Decimal{r}, &Decimal{r}).Value
		if got.Cmp(want) != 0 {
			t.Fatalf("round34(%s) = %s, want %s", r, got, want)
		}
	}
}

func TestDecimalDigitsMatchesString(t *testing.T) {
	rng := rand.New(rand.NewSource(2))
	for i := 0; i < 5000; i++ {
		n := new(big.Int).Rand(rng, decimalPow10(rng.Intn(200)+1))
		n.Add(n, big.NewInt(1))
		if got, want := decimalDigits(n), len(n.String()); got != want {
			t.Fatalf("digits(%s) = %d, want %d", n, got, want)
		}
	}
	for _, exp := range []int{1, 2, 18, 19, 20, 100} {
		p := decimalPow10(exp)
		if decimalDigits(p) != exp+1 || decimalDigits(new(big.Int).Sub(p, big.NewInt(1))) != exp {
			t.Errorf("boundary 10^%d", exp)
		}
	}
}

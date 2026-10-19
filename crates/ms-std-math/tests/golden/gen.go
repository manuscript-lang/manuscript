//go:build ignore

// gen prints reference results of Go's math package for the functions @std/math exposes.
// Usage: go run gen.go [count] > golden.txt   (lines: name hex-input... hex-output)
package main

import (
	"fmt"
	"math"
	"math/rand"
	"os"
	"strconv"
)

func main() {
	n := 120
	if len(os.Args) > 1 {
		n, _ = strconv.Atoi(os.Args[1])
	}
	r := rand.New(rand.NewSource(7))
	special := []float64{
		0, math.Copysign(0, -1), 1, -1, 2, -2, 0.5, -0.5, 0.25, 3, 10, 21, 22, -21, -22,
		math.Inf(1), math.Inf(-1), math.NaN(), math.MaxFloat64, -math.MaxFloat64,
		math.SmallestNonzeroFloat64, -math.SmallestNonzeroFloat64, 2.2250738585072014e-308,
		math.Pi, -math.Pi, math.Pi / 2, math.Pi / 4, 3 * math.Pi / 4, 1e-10, 1e-300, 1e10, 1e15,
		1e300, 536870912, 536870911.5, 1 << 53, 1<<53 + 2, 709.78, 710, -745.2, -746, 0.7, 0.66, 0.625,
		44.01, 44.02, 56 * math.Ln2, 0x1p-28, 0x1p-29, 0x1p-54, 0.4142135623730950, 2.4142135623730951,
		math.Nextafter(1, 2), math.Nextafter(1, 0), 4.5, 5.5, -4.5, 0.49999999999999994, 9007199254740993,
		1e19, 1.8446744073709552e19, 9.223372036854775808e18,
	}
	inputs := append([]float64{}, special...)
	for i := 0; i < n; i++ {
		inputs = append(inputs,
			(r.Float64()*2-1)*10,
			(r.Float64()*2-1)*1.5,
			(r.Float64()*2-1)*800,
			(r.Float64()*2-1)*math.Pow(10, float64(r.Intn(40)-20)),
			math.Float64frombits(r.Uint64()),
			float64(r.Intn(2000)-1000)/8,
			(r.Float64()*2 - 1) * 1e12,
		)
	}
	unary := []struct {
		name string
		f    func(float64) float64
	}{
		{"acos", math.Acos}, {"asin", math.Asin}, {"atan", math.Atan}, {"cos", math.Cos},
		{"cosh", math.Cosh}, {"exp", math.Exp}, {"log", math.Log}, {"log10", math.Log10},
		{"log2", math.Log2}, {"sin", math.Sin}, {"sinh", math.Sinh}, {"tan", math.Tan},
		{"tanh", math.Tanh}, {"acosh", math.Acosh}, {"asinh", math.Asinh}, {"atanh", math.Atanh},
		{"cbrt", math.Cbrt}, {"expm1", math.Expm1}, {"log1p", math.Log1p}, {"sqrt", math.Sqrt},
		{"floor", math.Floor}, {"ceil", math.Ceil}, {"trunc", math.Trunc},
		{"round", func(v float64) float64 {
			if math.IsNaN(v) || math.IsInf(v, 0) || v == 0 {
				return v
			}
			lower := math.Floor(v)
			if v-lower >= 0.5 {
				lower++
			}
			if lower == 0 {
				return math.Copysign(0, v)
			}
			return lower
		}},
	}
	for _, u := range unary {
		for _, x := range inputs {
			fmt.Printf("%s %016x %016x\n", u.name, math.Float64bits(x), math.Float64bits(u.f(x)))
		}
	}
	binary := []struct {
		name string
		f    func(a, b float64) float64
	}{
		{"atan2", math.Atan2}, {"hypot", math.Hypot}, {"pow", math.Pow}, {"mod", math.Mod},
	}
	for _, b := range binary {
		for i, x := range inputs {
			for _, y := range []float64{inputs[(i*7+3)%len(inputs)], inputs[(i*13+5)%len(inputs)], special[i%len(special)], float64(r.Intn(21) - 10), r.Float64()*8 - 4} {
				fmt.Printf("%s %016x %016x %016x\n", b.name, math.Float64bits(x), math.Float64bits(y), math.Float64bits(b.f(x, y)))
			}
		}
	}
}

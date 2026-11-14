package main

import (
	"fmt"
	"math"
)

func heat(n, steps int) int {
	a := make([]float64, n*n)
	b := make([]float64, n*n)
	for i := range a {
		if i%97 == 0 {
			a[i] = 100.0
		}
	}
	for s := 0; s < steps; s++ {
		for y := 1; y < n-1; y++ {
			for x := 1; x < n-1; x++ {
				i := y*n + x
				b[i] = a[i] + 0.2*(a[i-1]+a[i+1]+a[i-n]+a[i+n]-4.0*a[i])
			}
		}
		copy(a, b)
	}
	total := 0.0
	for _, v := range a {
		total += v
	}
	return int(total * 1000.0)
}

func mandelbrot(size, limit int) int {
	inside, work := 0, 0
	for py := 0; py < size; py++ {
		for px := 0; px < size; px++ {
			cr := float64(px)*3.0/float64(size) - 2.0
			ci := float64(py)*2.0/float64(size) - 1.0
			zr, zi, k := 0.0, 0.0, 0
			for k < limit && zr*zr+zi*zi <= 4.0 {
				t := zr*zr - zi*zi + cr
				zi = 2.0*zr*zi + ci
				zr = t
				k++
			}
			work += k
			if k == limit {
				inside++
			}
		}
	}
	return inside*1000003 + work%1000003
}

func norms(count int) int {
	total := 0.0
	for i := 1; i < count; i++ {
		f := float64(i)
		total += math.Sqrt(f*f + 3.0)
	}
	return int(total)
}

func main() {
	fmt.Printf("heat %d\n", heat(500, 120))
	fmt.Printf("mandelbrot %d\n", mandelbrot(700, 200))
	fmt.Printf("norms %d\n", norms(20000000))
}

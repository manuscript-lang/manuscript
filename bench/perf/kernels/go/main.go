package main

import (
	"fmt"
	"time"
)

type Body struct{ x, y, z, vx, vy, vz, mass float64 }
type Grid struct {
	width, height int
	cells         []int
}
type Tree struct{ l, r *Tree }

func sieve(n int) int {
	flags := make([]bool, 0)
	for i := 0; i <= n; i++ {
		flags = append(flags, true)
	}
	count := 0
	for i := 2; i <= n; i++ {
		if flags[i] {
			count++
			for j := i * i; j <= n; j += i {
				flags[j] = false
			}
		}
	}
	return count
}

func advance(b []*Body, steps int) float64 {
	n := len(b)
	for s := 0; s < steps; s++ {
		for i := 0; i < n; i++ {
			a := b[i]
			for j := i + 1; j < n; j++ {
				c := b[j]
				dx, dy, dz := a.x-c.x, a.y-c.y, a.z-c.z
				d2 := dx*dx + dy*dy + dz*dz + 0.01
				mag := 0.01 / (d2 * d2)
				a.vx -= dx * c.mass * mag
				a.vy -= dy * c.mass * mag
				a.vz -= dz * c.mass * mag
				c.vx += dx * a.mass * mag
				c.vy += dy * a.mass * mag
				c.vz += dz * a.mass * mag
			}
		}
		for i := 0; i < n; i++ {
			a := b[i]
			a.x += 0.01 * a.vx
			a.y += 0.01 * a.vy
			a.z += 0.01 * a.vz
		}
	}
	e := 0.0
	for _, a := range b {
		e += a.mass * (a.vx*a.vx + a.vy*a.vy + a.vz*a.vz)
	}
	return e
}

func cell(g *Grid, x, y int) int {
	wx := (x + g.width) % g.width
	wy := (y + g.height) % g.height
	return g.cells[wy*g.width+wx]
}
func neighbors(g *Grid, x, y int) int {
	n := 0
	for dy := -1; dy <= 1; dy++ {
		for dx := -1; dx <= 1; dx++ {
			if !(dx == 0 && dy == 0) {
				n += cell(g, x+dx, y+dy)
			}
		}
	}
	return n
}
func step(g *Grid) *Grid {
	next := make([]int, 0)
	for y := 0; y < g.height; y++ {
		for x := 0; x < g.width; x++ {
			n := neighbors(g, x, y)
			alive := cell(g, x, y) == 1
			if n == 3 || (alive && n == 2) {
				next = append(next, 1)
			} else {
				next = append(next, 0)
			}
		}
	}
	return &Grid{g.width, g.height, next}
}
func life(gens int) int {
	cells := make([]int, 0)
	for i := 0; i < 128*128; i++ {
		if i%7 == 0 || i%11 == 0 {
			cells = append(cells, 1)
		} else {
			cells = append(cells, 0)
		}
	}
	g := &Grid{128, 128, cells}
	for n := 0; n < gens; n++ {
		g = step(g)
	}
	s := 0
	for _, v := range g.cells {
		s += v
	}
	return s
}

func matmul(n int) float64 {
	a := make([][]float64, 0)
	b := make([][]float64, 0)
	for i := 0; i < n; i++ {
		ra := make([]float64, 0)
		rb := make([]float64, 0)
		for j := 0; j < n; j++ {
			ra = append(ra, float64(i+j))
			rb = append(rb, float64(i-j))
		}
		a = append(a, ra)
		b = append(b, rb)
	}
	total := 0.0
	for i := 0; i < n; i++ {
		for j := 0; j < n; j++ {
			s := 0.0
			for k := 0; k < n; k++ {
				s += a[i][k] * b[k][j]
			}
			total += s
		}
	}
	return total
}

func make_(d int) *Tree {
	if d == 0 {
		return nil
	}
	return &Tree{make_(d - 1), make_(d - 1)}
}
func check(t *Tree) int {
	if t == nil {
		return 1
	}
	return 1 + check(t.l) + check(t.r)
}
func trees(r int) int {
	t := 0
	for i := 0; i < r; i++ {
		t += check(make_(16))
	}
	return t
}
func collatz(limit int) int {
	best := 0
	for n := 1; n < limit; n++ {
		x, steps := n, 0
		for x != 1 {
			if x%2 == 0 {
				x = x / 2
			} else {
				x = 3*x + 1
			}
			steps++
		}
		if steps > best {
			best = steps
		}
	}
	return best
}
func wordfreq(n int) int {
	m := map[int]int{}
	for i := 0; i < n; i++ {
		m[(i*7919)%5003]++
	}
	return len(m)
}

func timed(name string, f func() int) {
	t := time.Now()
	r := f()
	fmt.Printf("%s %d %d\n", name, time.Since(t).Microseconds(), r)
}

func main() {
	timed("sieve_5M", func() int { return sieve(5000000) })
	timed("nbody_200k", func() int {
		b := []*Body{{0, 0, 0, 0, 0, 0, 10}, {1, 0, 0, 0, 1, 0, 1}, {0, 2, 0, 1, 0, 0, 1}, {0, 0, 3, 0, 0, 1, 1}, {4, 4, 0, 0, 0, 0, 0.5}}
		return int(advance(b, 200000) * 1000)
	})
	timed("life_128x128_50", func() int { return life(50) })
	timed("matmul_200", func() int { return int(matmul(200)) })
	timed("trees_d16_x20", func() int { return trees(20) })
	timed("collatz_1M", func() int { return collatz(1000000) })
	timed("map_count_2M", func() int { return wordfreq(2000000) })
}

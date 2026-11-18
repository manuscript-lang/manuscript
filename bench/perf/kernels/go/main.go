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

type Cx struct{ re, im float64 }

func (a Cx) mul(o Cx) Cx { return Cx{a.re*o.re - a.im*o.im, a.re*o.im + a.im*o.re} }
func (a Cx) add(o Cx) Cx { return Cx{a.re + o.re, a.im + o.im} }
func (a Cx) norm2() float64 { return a.re*a.re + a.im*a.im }

func mandel(n int) int {
	total := 0
	for y := 0; y < n; y++ {
		for x := 0; x < n; x++ {
			c := Cx{3.0*float64(x)/float64(n) - 2.0, 2.0*float64(y)/float64(n) - 1.0}
			z := Cx{0, 0}
			i := 0
			for i < 100 && z.norm2() < 4.0 {
				z = z.mul(z).add(c)
				i++
			}
			total += i
		}
	}
	return total
}

type Particle struct{ x, y, vx, vy float64 }

func particles(n, steps int) int {
	ps := []Particle{}
	for i := 0; i < n; i++ {
		f := float64(i)
		ps = append(ps, Particle{f, f * 0.5, 1.0, -1.0})
	}
	for s := 0; s < steps; s++ {
		for i := 0; i < n; i++ {
			p := ps[i]
			p.x += p.vx * 0.01
			p.y += p.vy * 0.01
			if p.x > 100.0 {
				p.vx = -p.vx
			}
			ps[i] = p
		}
	}
	e := 0.0
	for _, p := range ps {
		e += p.x + p.y
	}
	return int(e)
}

const (
	opPush = iota
	opAdd
	opMul
	opDup
	opSwap
	opPop
	opJmpNz
	opDec
)

type Op struct{ kind, arg int }

func vm(iters int) int {
	code := []Op{{opPush, 3}, {opPush, 7}, {opMul, 0}, {opPop, 0}, {opDec, 0}, {opJmpNz, 0}, {opPop, 0}}
	stack := []int{iters}
	pop := func() int {
		if len(stack) == 0 {
			return 0
		}
		v := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		return v
	}
	pc, acc := 0, 0
	for pc < len(code) {
		op := code[pc]
		switch op.kind {
		case opPush:
			stack = append(stack, op.arg)
			pc++
		case opAdd:
			b := pop()
			a := pop()
			stack = append(stack, a+b)
			pc++
		case opMul:
			b := pop()
			a := pop()
			stack = append(stack, a*b%1000003)
			pc++
		case opDup:
			stack = append(stack, stack[len(stack)-1])
			pc++
		case opSwap:
			b := pop()
			a := pop()
			stack = append(stack, b, a)
			pc++
		case opPop:
			acc += pop()
			pc++
		case opJmpNz:
			if stack[len(stack)-1] != 0 {
				pc = op.arg
			} else {
				pc++
			}
		case opDec:
			v := pop()
			stack = append(stack, v-1)
			pc++
		}
	}
	return acc
}

type Expr struct {
	kind, n int
	l, r    *Expr
}

func build(d, s int) *Expr {
	if d == 0 {
		return &Expr{kind: 0, n: s % 10}
	}
	if d%2 == 0 {
		l := build(d-1, s*3+1)
		r := build(d-1, s*7+2)
		return &Expr{kind: 1, l: l, r: r}
	}
	l := build(d-1, s+1)
	r := build(d-1, s+3)
	return &Expr{kind: 2, l: l, r: r}
}

func eval(e *Expr) int {
	switch e.kind {
	case 0:
		return e.n
	case 1:
		return (eval(e.l) + eval(e.r)) % 1000003
	}
	return eval(e.l) * eval(e.r) % 1000003
}

func exprs(d, reps int) int {
	e := build(d, 1)
	t := 0
	for i := 0; i < reps; i++ {
		t += eval(e)
	}
	return t
}

func closures(n int) int {
	k := 7
	f := func(x int) int { return x*k + 1 }
	t := 0
	for i := 0; i < n; i++ {
		t += f(i) % 13
	}
	xs := make([]int, 1000)
	for i := range xs {
		xs[i] = i * k
	}
	for r := 0; r < n/1000; r++ {
		for _, x := range xs {
			v := x + k
			if v%3 == 0 {
				t += v
			}
		}
	}
	return t
}

func stencil(n, iters int) int {
	a := make([]int, n*n)
	b := make([]int, n*n)
	for i := range a {
		a[i] = i % 17
	}
	for it := 0; it < iters; it++ {
		for y := 1; y < n-1; y++ {
			for x := 1; x < n-1; x++ {
				v := a[y*n+x-1] + a[y*n+x+1] + a[(y-1)*n+x] + a[(y+1)*n+x]
				b[y*n+x] = v % 1009
			}
		}
		a, b = b, a
	}
	s := 0
	for _, v := range a {
		s += v
	}
	return s
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
	timed("mandel_400", func() int { return mandel(400) })
	timed("particles_1k_5k", func() int { return particles(1000, 5000) })
	timed("vm_5M", func() int { return vm(5000000) })
	timed("expr_d20_x20", func() int { return exprs(20, 20) })
	timed("closures_20M", func() int { return closures(20000000) })
	timed("stencil_1000_20", func() int { return stencil(1000, 20) })
}

package main

import (
	"bufio"
	"errors"
	"fmt"
	"os"
	"strings"
	"time"
)

type Counter interface{ Bump(by int) int }
type Acc struct{ total int }

func (a *Acc) Bump(by int) int { a.total += by; return a.total }

type Shape interface{ isShape() }
type Circle struct{ r int }
type Square struct{ s int }
type Tri struct{ b int }

func (Circle) isShape() {}
func (Square) isShape() {}
func (Tri) isShape()    {}

//go:noinline
func ident[T any](x T) T { return x }

//go:noinline
func checked(n int) (int, error) {
	if n < 0 {
		return 0, errors.New("negative")
	}
	return n + 1, nil
}

//go:noinline
func chain(n int) (int, error) {
	v, err := checked(n)
	if err != nil {
		return 0, err
	}
	return v, nil
}

//go:noinline
func area(s Shape) int {
	out := 0
	switch v := s.(type) {
	case Circle:
		out = v.r * 3
	case Square:
		out = v.s * v.s
	case Tri:
		out = v.b
	}
	return out
}

func report(name string, ops int, start time.Time) {
	fmt.Printf("%s %d %d\n", name, ops, time.Since(start).Nanoseconds())
}

var sink int

func main() {
	t := time.Now()
	var sb strings.Builder
	for i := 0; i < 50000; i++ {
		sb.WriteString("x")
	}
	built := sb.String()
	report("string_append_50k", 50000, t)

	t = time.Now()
	lines := 0
	r := bufio.NewReader(os.Stdin)
	for {
		_, err := r.ReadString('\n')
		if err != nil {
			break
		}
		lines++
	}
	report("read_line", lines, t)

	t = time.Now()
	m := map[int]int{}
	for i := 0; i < 8000; i++ {
		m[i] = i * 2
	}
	sum := 0
	for i := 0; i < 8000; i++ {
		sum += m[i]
	}
	report("map_put_get_8k", 16000, t)

	t = time.Now()
	hits := 0
	for i := 0; i < 10000000; i++ {
		if i%3 == 0 {
			hits++
		}
	}
	report("int_eq", 10000000, t)

	t = time.Now()
	g := 0
	for i := 0; i < 1000000; i++ {
		g += ident[int](i)
	}
	report("generic_call", 1000000, t)

	t = time.Now()
	acc := &Acc{}
	var c Counter = acc
	for i := 0; i < 1000000; i++ {
		c.Bump(1)
	}
	report("method_call", 1000000, t)

	t = time.Now()
	tr := 0
	for i := 0; i < 1000000; i++ {
		if v, err := chain(i); err == nil {
			tr += v
		} else {
			tr--
		}
	}
	report("try", 1000000, t)

	t = time.Now()
	shapes := []Shape{Circle{2}, Square{3}, Tri{4}}
	ma := 0
	for i := 0; i < 1000000; i++ {
		ma += area(shapes[i%3])
	}
	report("match", 1000000, t)

	xs := make([]int, 0)
	for i := 0; i < 100; i++ {
		xs = append(xs, i)
	}
	t = time.Now()
	ln := 0
	for i := 0; i < 1000000; i++ {
		ln += len(xs)
	}
	report("builtin_length", 1000000, t)

	big := make([]int, 0)
	for i := 0; i < 1000000; i++ {
		big = append(big, i)
	}
	t = time.Now()
	fs := 0
	for _, x := range big {
		fs += x
	}
	report("for_list", 1000000, t)

	fmt.Printf("# sink %d %d %d %d %d %d %d %d %d\n", len(built), sum, hits, g, acc.total, tr, ma, ln, fs)
}

package main

import "fmt"

type Shape interface {
	Area() int
	Grow(by int) int
}
type Sq struct{ s int }
type Rect struct{ w, h int }
type Tri struct{ b, h int }

func (q Sq) Area() int         { return q.s * q.s }
func (q Sq) Grow(by int) int   { return (q.s + by) * (q.s + by) }
func (r Rect) Area() int       { return r.w * r.h }
func (r Rect) Grow(by int) int { return (r.w + by) * (r.h + by) }
func (t Tri) Area() int        { return t.b * t.h / 2 }
func (t Tri) Grow(by int) int  { return (t.b + by) * (t.h + by) / 2 }

func shapes(n int) int {
	xs := []Shape{}
	for i := 0; i < n; i++ {
		switch i % 3 {
		case 0:
			xs = append(xs, Sq{i%10 + 1})
		case 1:
			xs = append(xs, Rect{i%7 + 1, i%5 + 1})
		default:
			xs = append(xs, Tri{i%9 + 1, i%4 + 1})
		}
	}
	total := 0
	for pass := 0; pass < 20; pass++ {
		for _, s := range xs {
			total += s.Area() + s.Grow(pass)
		}
	}
	return total
}

func closures(n int) int {
	offset := 3
	steps := []func(int) int{
		func(x int) int { return x + offset },
		func(x int) int { return x * 2 },
		func(x int) int { return x - 1 },
		func(x int) int { return x % 1000003 },
	}
	acc := 1
	for i := 0; i < n; i++ {
		for _, f := range steps {
			acc = f(acc + i)
		}
	}
	return acc
}

type Stack[T any] struct{ items []T }

func (s *Stack[T]) Push(v T) { s.items = append(s.items, v) }
func (s *Stack[T]) Pop() (T, bool) {
	var zero T
	if len(s.items) == 0 {
		return zero, false
	}
	v := s.items[len(s.items)-1]
	s.items = s.items[:len(s.items)-1]
	return v, true
}

func foldWith[T any](xs []T, init int, step func(int, T) int) int {
	acc := init
	for _, x := range xs {
		acc = step(acc, x)
	}
	return acc
}

func generics(n int) int {
	s := &Stack[int]{}
	t := 0
	for i := 0; i < n; i++ {
		s.Push(i % 1000)
		if i%3 == 2 {
			if v, ok := s.Pop(); ok {
				t += v
			}
		}
	}
	return t + foldWith(s.items, 0, func(a, x int) int { return a + x*2 })
}

func main() {
	fmt.Printf("shapes %d\n", shapes(1000000))
	fmt.Printf("closures %d\n", closures(15000000))
	fmt.Printf("generics %d\n", generics(20000000))
}

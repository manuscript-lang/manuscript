package main

import (
	"fmt"
	"slices"
	"strconv"
	"strings"
	"time"
)

type Shape interface{ Area() int }
type Sq struct{ s int }
type Rect struct{ w, h int }
type Tri struct{ b, h int }

func (s Sq) Area() int   { return s.s * s.s }
func (r Rect) Area() int { return r.w * r.h }
func (t Tri) Area() int  { return t.b * t.h / 2 }

type Item struct {
	key  int
	name string
}
type Fail struct{ code int }

func (Fail) Error() string { return "fail" }

func fib(n int) int {
	if n < 2 {
		return n
	}
	return fib(n-1) + fib(n-2)
}

func dispatch(n int) int {
	shapes := []Shape{Sq{3}, Rect{2, 5}, Tri{4, 6}, Sq{7}}
	t := 0
	for i := 0; i < n; i++ {
		t += shapes[i%4].Area()
	}
	return t
}

func closures(n int) int {
	base := 3
	f := func(x int) int { return x*base + 1 }
	t := 0
	for i := 0; i < n; i++ {
		t += f(i)
	}
	return t
}

func sorting(n int) int {
	v := make([]int, 0)
	for i := 0; i < n; i++ {
		v = append(v, i*7919%1000003)
	}
	s := slices.Clone(v)
	slices.SortFunc(s, func(a, b int) int {
		if a < b {
			return -1
		}
		if a > b {
			return 1
		}
		return 0
	})
	return s[0] + s[n/2] + s[n-1]
}

func text(n int) int {
	var b strings.Builder
	for i := 0; i < n; i++ {
		b.WriteString(strconv.Itoa(i * 31 % 1000))
		b.WriteString(",")
	}
	parts := strings.Split(b.String(), ",")
	t := 0
	for _, p := range parts {
		v, _ := strconv.Atoi(p)
		t += v
	}
	return t
}

func wordMap(n int) int {
	words := make([]string, 1000)
	for i := range words {
		words[i] = "word" + strconv.Itoa(i)
	}
	m := map[string]int{}
	for j := 0; j < n; j++ {
		m[words[j*7%1000]]++
	}
	return len(m) + m["word7"]
}

func check(i int) (int, error) {
	if i%1000 == 999 {
		return 0, Fail{i}
	}
	return i, nil
}
func step(i int) (int, error) {
	v, err := check(i)
	if err != nil {
		return 0, err
	}
	return v + 1, nil
}
func errors(n int) int {
	t := 0
	for i := 0; i < n; i++ {
		if v, err := step(i); err == nil {
			t += v
		} else {
			t += 7
		}
	}
	return t
}

func records(n int) int {
	items := make([]Item, 0)
	for i := 0; i < n; i++ {
		items = append(items, Item{i * 7919 % 10007, "n" + strconv.Itoa(i%100)})
	}
	t := 0
	for r := 0; r < 20; r++ {
		for _, it := range items {
			t += it.key + len(it.name)
		}
	}
	return t
}

func timed(name string, f func() int) {
	t := time.Now()
	r := f()
	fmt.Printf("%s %d %d\n", name, time.Since(t).Microseconds(), r)
}

func main() {
	timed("call_fib_36", func() int { return fib(36) })
	timed("dispatch_100M", func() int { return dispatch(100000000) })
	timed("closure_100M", func() int { return closures(100000000) })
	timed("sort_1M", func() int { return sorting(1000000) })
	timed("text_1M", func() int { return text(1000000) })
	timed("strmap_10M", func() int { return wordMap(10000000) })
	timed("errors_50M", func() int { return errors(50000000) })
	timed("records_1M_x20", func() int { return records(1000000) })
}

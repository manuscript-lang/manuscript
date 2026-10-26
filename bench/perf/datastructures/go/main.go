package main

import (
	"container/heap"
	"fmt"
	"slices"
	"sort"
	"strings"
	"time"
)

type rec struct{ key, id int }

type ih []int

func (h ih) Len() int           { return len(h) }
func (h ih) Less(i, j int) bool { return h[i] < h[j] }
func (h ih) Swap(i, j int)      { h[i], h[j] = h[j], h[i] }
func (h *ih) Push(x any)        { *h = append(*h, x.(int)) }
func (h *ih) Pop() any {
	o := *h
	n := len(o)
	x := o[n-1]
	*h = o[:n-1]
	return x
}

func nextRand(x int) int { return (x*1103515245 + 12345) % 2147483648 }

func report(name string, ops int, t time.Time) {
	fmt.Printf("%s %d %d\n", name, ops, time.Since(t).Nanoseconds())
}

func main() {
	total := 0
	n := 1000000

	t := time.Now()
	var l []int
	for i := 0; i < n; i++ {
		l = append(l, i)
	}
	report("list_append", n, t)
	total += len(l)

	t = time.Now()
	x := 1
	sum := 0
	for i := 0; i < n; i++ {
		x = nextRand(x)
		sum += l[x%n]
	}
	report("list_get_random", n, t)
	total += sum

	data := make([]int, 0, n)
	x = 1
	for i := 0; i < n; i++ {
		x = nextRand(x)
		data = append(data, x)
	}
	t = time.Now()
	s := slices.Clone(data)
	slices.SortStableFunc(s, func(a, b int) int {
		if a < b {
			return -1
		} else if a > b {
			return 1
		}
		return 0
	})
	report("list_sort_int", n, t)
	total += s[0]

	m := 300000
	recs := make([]rec, 0, m)
	x = 1
	for i := 0; i < m; i++ {
		x = nextRand(x)
		recs = append(recs, rec{x % 100000, i})
	}
	t = time.Now()
	rs := slices.Clone(recs)
	sort.SliceStable(rs, func(i, j int) bool { return rs[i].key < rs[j].key })
	report("list_sort_cmp", m, t)
	total += rs[0].id

	t = time.Now()
	mi := map[int]int{}
	x = 1
	for i := 0; i < n; i++ {
		x = nextRand(x)
		mi[x] = i
	}
	hits := 0
	x = 1
	for i := 0; i < n; i++ {
		x = nextRand(x)
		hits += mi[x]
	}
	report("map_int_put_get", n*2, t)
	total += hits

	k := 200000
	keys := make([]string, 0, k)
	for i := 0; i < k; i++ {
		keys = append(keys, fmt.Sprintf("key%d", i))
	}
	t = time.Now()
	ms := map[string]int{}
	for i := 0; i < k; i++ {
		ms[keys[i]] = i
	}
	hits = 0
	for i := 0; i < k; i++ {
		hits += ms[keys[i]]
	}
	report("map_str_put_get", k*2, t)
	total += hits

	t = time.Now()
	set := map[int]struct{}{}
	x = 1
	for i := 0; i < n; i++ {
		x = nextRand(x)
		set[x] = struct{}{}
	}
	hits = 0
	x = 1
	for i := 0; i < n; i++ {
		x = nextRand(x)
		if _, ok := set[x]; ok {
			hits++
		}
	}
	report("set_int_add_contains", n*2, t)
	total += hits

	w := 200000
	t = time.Now()
	var sb strings.Builder
	for i := 0; i < w; i++ {
		sb.WriteString("word")
		sb.WriteString(" ")
	}
	text := sb.String()
	parts := strings.Split(text, " ")
	joined := strings.Join(parts, "-")
	replaced := strings.ReplaceAll(joined, "word", "w")
	report("string_build_split_join_replace", w, t)
	total += len(replaced) + len(parts)

	b := 4000000
	t = time.Now()
	var bb []byte
	for i := 0; i < b; i++ {
		bb = append(bb, byte(i%256))
	}
	report("bytes_append", b, t)
	total += len(bb)

	p := 300000
	t = time.Now()
	h := &ih{}
	x = 1
	for i := 0; i < p; i++ {
		x = nextRand(x)
		heap.Push(h, x)
	}
	sum = 0
	for i := 0; i < p; i++ {
		sum += heap.Pop(h).(int)
	}
	report("pq_int_enqueue_dequeue", p*2, t)
	total += sum
	if total == 0 {
		println("zero")
	}
}

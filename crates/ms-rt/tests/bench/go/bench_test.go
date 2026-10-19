package bench

import (
	"sort"
	"strings"
	"testing"
)

const n = 2000000

func BenchmarkListPushInt(b *testing.B) {
	for b.Loop() {
		var v []int
		for i := 0; i < n; i++ {
			v = append(v, (i*2654435761)%1000003)
		}
	}
}

func BenchmarkListSortInt(b *testing.B) {
	for b.Loop() {
		b.StopTimer()
		v := make([]int, n)
		for i := range v {
			v[i] = (i * 2654435761) % 1000003
		}
		b.StartTimer()
		sort.SliceStable(v, func(a, c int) bool { return v[a] < v[c] })
	}
}

func BenchmarkMapInsertInt(b *testing.B) {
	for b.Loop() {
		m := map[int]int{}
		for i := 0; i < n/2; i++ {
			m[i*7] = i
		}
	}
}

func BenchmarkMapGetInt(b *testing.B) {
	m := map[int]int{}
	for i := 0; i < n/2; i++ {
		m[i*7] = i
	}
	b.ResetTimer()
	for b.Loop() {
		h := 0
		for i := 0; i < n/2; i++ {
			h += m[i*7]
		}
		_ = h
	}
}

func BenchmarkStringConcatLen(b *testing.B) {
	s := "ab"
	for b.Loop() {
		h := 0
		for i := 0; i < n/10; i++ {
			h += len(strings.Clone(s + s))
		}
		_ = h
	}
}

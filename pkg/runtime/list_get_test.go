package msruntime

import (
	"fmt"
	"math"
	"testing"
)

func TestListGetIndexBoundaries(t *testing.T) {
	values := NewList(10, 20, 30)
	for _, tc := range []struct {
		index, want int
	}{
		{0, 10}, {2, 30}, {-1, 30}, {-3, 10},
		{3, -7}, {-4, -7}, {math.MaxInt, -7}, {math.MinInt, -7},
	} {
		t.Run(fmt.Sprint(tc.index), func(t *testing.T) {
			if got := List_Get(tctx, values, tc.index, Some(-7)); got != tc.want {
				t.Fatalf("get(%d) = %d, want %d", tc.index, got, tc.want)
			}
		})
	}
	for _, index := range []int{0, -1, math.MinInt, math.MaxInt} {
		if got := List_Get(tctx, NewList[int](), index, Some(-7)); got != -7 {
			t.Fatalf("empty list get(%d) = %d", index, got)
		}
	}
	for _, index := range []int{3, -4, math.MinInt, math.MaxInt} {
		mustFault(t, fmt.Sprintf("index %d out of range for length 3", index), func() {
			List_Get(tctx, values, index, None[int]())
		})
	}
}

func TestListGetKeepsElementAndDefaultAliases(t *testing.T) {
	value, fallback := NewList(1), NewList(2)
	values := NewList(value)
	for _, index := range []int{0, -1} {
		if got := List_Get(tctx, values, index, Some(fallback)); got != value {
			t.Fatal("element identity changed")
		}
	}
	if got := List_Get(tctx, values, 1, Some(fallback)); got != fallback {
		t.Fatal("default identity changed")
	}
}

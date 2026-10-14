package msruntime

import (
	"testing"
	"time"
)

func intSet(from, to int64) *Set {
	s := &Set{Type: "@std/Set[Int]"}
	ctx := RootExecution()
	for i := from; i < to; i++ {
		s.add(ctx, i)
	}
	return s
}

func reversedSet(s *Set) *Set {
	out := &Set{Type: s.Type}
	ctx := RootExecution()
	for i := len(s.Items) - 1; i >= 0; i-- {
		out.add(ctx, s.Items[i])
	}
	return out
}

func TestSetAndMapEqualityIsOrderInsensitive(t *testing.T) {
	ctx := RootExecution()
	scope := TypeScope{}
	a := intSet(0, 50)
	if !EqualSelected(ctx, a, reversedSet(a), scope) || EqualSelected(ctx, a, intSet(1, 51), scope) || EqualSelected(ctx, a, intSet(0, 49), scope) {
		t.Fatal("set equality ignores order, not membership")
	}

	left := &Map{Type: "@std/Map[Point][Int]"}
	right := &Map{Type: left.Type}
	for i := int64(0); i < 20; i++ {
		left.put(ctx, pointKey(i, i), i)
		right.put(ctx, pointKey(19-i, 19-i), 19-i)
	}
	if !EqualSelected(ctx, left, right, scope) {
		t.Fatal("maps with the same entries in another order compared unequal")
	}
	right.put(ctx, pointKey(3, 3), int64(-1))
	if EqualSelected(ctx, left, right, scope) {
		t.Fatal("maps with a different value compared equal")
	}
	right.put(ctx, pointKey(3, 3), int64(3))
	right.removeAt(ctx, right.find(ctx, pointKey(4, 4)))
	right.put(ctx, pointKey(40, 40), int64(4))
	if EqualSelected(ctx, left, right, scope) {
		t.Fatal("maps with a different key compared equal")
	}
}

// Comparing two n-element collections scanned every pair, so 50,000 elements
// took over a minute; the hash index makes it linear.
func TestSetAndMapEqualityIsNotQuadratic(t *testing.T) {
	ctx := RootExecution()
	scope := TypeScope{}
	const n = 50000
	a := intSet(0, n)
	b := reversedSet(a)
	m1 := &Map{Type: "@std/Map[Int][Int]"}
	m2 := &Map{Type: m1.Type}
	for i := int64(0); i < n; i++ {
		m1.put(ctx, i, i)
		m2.put(ctx, n-1-i, n-1-i)
	}
	start := time.Now()
	if !EqualSelected(ctx, a, b, scope) || !EqualSelected(ctx, m1, m2, scope) {
		t.Fatal("equal collections compared unequal")
	}
	if EqualSelected(ctx, a, intSet(1, n+1), scope) {
		t.Fatal("different sets compared equal")
	}
	if elapsed := time.Since(start); elapsed > 5*time.Second {
		t.Fatalf("comparing %d-element collections took %v", n, elapsed)
	}
}

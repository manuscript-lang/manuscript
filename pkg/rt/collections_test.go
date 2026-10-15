package rt

import (
	"context"
	"math"
	"reflect"
	"strings"
	"testing"
)

func fault(t *testing.T, want string, f func()) {
	t.Helper()
	defer func() {
		t.Helper()
		r := recover()
		got, ok := r.(Fault)
		if !ok {
			t.Fatalf("want fault %q, got %v", want, r)
		}
		if !strings.Contains(got.Message, want) {
			t.Fatalf("fault = %q, want %q", got.Message, want)
		}
	}()
	f()
}

func ints(items ...int64) *List[int64] { return NewList(items...) }

func eqInt(_ *Execution, a, b int64) bool { return a == b }

func TestListAccessAndMutation(t *testing.T) {
	ctx := RootExecution()
	l := ints(1, 2, 3)
	if got := List_At(ctx, l, -1); got != Some(int64(3)) {
		t.Fatalf("at(-1) = %v", got)
	}
	if List_At(ctx, l, 3).Some || List_At(ctx, l, -4).Some || List_At(ctx, l, math.MinInt64).Some {
		t.Fatal("out of range at must be none")
	}
	if List_First(ctx, ints()).Some || List_Last(ctx, ints()).Some {
		t.Fatal("empty first/last")
	}
	List_Prepend(ctx, l, 0)
	List_Insert(ctx, l, -1, 9)
	List_Insert(ctx, l, 5, 7)
	if want := []int64{0, 1, 2, 9, 3, 7}; !reflect.DeepEqual(l.Items, want) {
		t.Fatalf("items = %v", l.Items)
	}
	fault(t, "List.insert: index must be between -6 and 6 (negative indexes count from the end), found 7", func() { List_Insert(ctx, l, 7, 1) })
	if got := List_Pop(ctx, l); got != Some(int64(7)) {
		t.Fatalf("pop = %v", got)
	}
	List_Set(ctx, l, -1, 8)
	List_Remove(ctx, l, 0)
	if want := []int64{1, 2, 9, 8}; !reflect.DeepEqual(l.Items, want) {
		t.Fatalf("items = %v", l.Items)
	}
	fault(t, "List.set: index must be between -4 and 3 (negative indexes count from the end), found 4", func() { List_Set(ctx, l, 4, 0) })
	fault(t, "List.remove: index has no valid value for an empty collection, found 0", func() { List_Remove(ctx, ints(), 0) })
	if List_Pop(ctx, ints()).Some {
		t.Fatal("pop empty")
	}
}

func TestListSliceTakeDrop(t *testing.T) {
	ctx := RootExecution()
	l := ints(1, 2, 3, 4)
	r := List_Slice(ctx, l, 1, -1)
	if r.Failed || !reflect.DeepEqual(r.Val.Items, []int64{2, 3}) {
		t.Fatalf("slice = %v", r)
	}
	r.Val.Items[0] = 99
	if l.Items[1] != 2 {
		t.Fatal("slice must copy")
	}
	for _, b := range [][2]int64{{3, 1}, {0, 5}, {-5, 2}} {
		if got := List_Slice(ctx, l, b[0], b[1]); !got.Failed || got.Err != (CollectionError_OutOfRange{}) {
			t.Fatalf("slice %v = %v", b, got)
		}
	}
	if got := List_Take(ctx, l, 10).Items; !reflect.DeepEqual(got, []int64{1, 2, 3, 4}) {
		t.Fatal(got)
	}
	if got := List_Drop(ctx, l, 3).Items; !reflect.DeepEqual(got, []int64{4}) {
		t.Fatal(got)
	}
	fault(t, "List.take: count must be nonnegative, found -1", func() { List_Take(ctx, l, -1) })
	fault(t, "List.drop: count must be nonnegative, found -2", func() { List_Drop(ctx, l, -2) })
}

func TestListSpliceFillCopyWithin(t *testing.T) {
	ctx := RootExecution()
	l := ints(1, 2, 3, 4)
	List_Splice(ctx, l, 1, 2, ints(7, 8, 9))
	if want := []int64{1, 7, 8, 9, 4}; !reflect.DeepEqual(l.Items, want) {
		t.Fatal(l.Items)
	}
	List_Splice(ctx, l, 0, 1, l)
	if want := []int64{1, 7, 8, 9, 4, 7, 8, 9, 4}; !reflect.DeepEqual(l.Items, want) {
		t.Fatal(l.Items)
	}
	fault(t, "List.splice: start must be between 0 and 9, found 10", func() { List_Splice(ctx, l, 10, 0, ints()) })
	fault(t, "List.splice: delete_count must be between 0 and 8, found 9", func() { List_Splice(ctx, l, 1, 9, ints()) })
	m := ints(1, 2, 3, 4, 5)
	List_Fill(ctx, m, 0, 1, 3)
	List_CopyWithin(ctx, m, 3, 0, 2)
	if want := []int64{1, 0, 0, 1, 0}; !reflect.DeepEqual(m.Items, want) {
		t.Fatal(m.Items)
	}
	fault(t, "List.fill: start/end must satisfy 0 <= start <= end <= 5; found start 3 and end 2", func() { List_Fill(ctx, m, 0, 3, 2) })
	fault(t, "List.copy_within: target must be between 0 and 5, found 6", func() { List_CopyWithin(ctx, m, 6, 0, 1) })
}

func TestListQueriesAndCallbacks(t *testing.T) {
	ctx := RootExecution()
	l := ints(3, 1, 2, 1)
	if !List_Contains(ctx, eqInt, l, 2) || List_Contains(ctx, eqInt, l, 5) {
		t.Fatal("contains")
	}
	if List_IndexOf(ctx, eqInt, l, 1) != Some(int64(1)) || List_LastIndexOf(ctx, eqInt, l, 1) != Some(int64(3)) {
		t.Fatal("index_of")
	}
	odd := func(_ *Execution, v int64) bool { return v%2 == 1 }
	if List_Find(ctx, l, odd) != Some(int64(3)) || List_FindLast(ctx, l, odd) != Some(int64(1)) {
		t.Fatal("find")
	}
	if List_FindIndex(ctx, l, odd) != Some(int64(0)) || List_FindLastIndex(ctx, l, odd) != Some(int64(3)) {
		t.Fatal("find_index")
	}
	if List_Count(ctx, l, odd) != 3 || !List_Some(ctx, l, odd) || List_Every(ctx, l, odd) || !List_Every(ctx, ints(), odd) {
		t.Fatal("count/some/every")
	}
	if got := List_Distinct(ctx, eqInt, l).Items; !reflect.DeepEqual(got, []int64{3, 1, 2}) {
		t.Fatal(got)
	}
	sum := List_Fold(ctx, l, "", func(_ *Execution, a string, v int64) string { return a + FormatInt(v) })
	right := List_FoldRight(ctx, l, "", func(_ *Execution, a string, v int64) string { return a + FormatInt(v) })
	if sum != "3121" || right != "1213" {
		t.Fatal(sum, right)
	}
	flat := List_FlatMap(ctx, l, func(_ *Execution, v int64) *List[int64] { return ints(v, v) })
	if len(flat.Items) != 8 {
		t.Fatal(flat.Items)
	}
	groups := List_GroupBy(ctx, nil, l, func(_ *Execution, v int64) bool { return v > 1 })
	if keys := Map_Keys(ctx, groups).Items; !reflect.DeepEqual(keys, []bool{true, false}) {
		t.Fatal(keys)
	}
	if got, _ := groups.Lookup(false); !reflect.DeepEqual(got.Items, []int64{1, 1}) {
		t.Fatal(got.Items)
	}
	if got := List_Join(ctx, NewList("a", "b", "c"), ", "); got != "a, b, c" {
		t.Fatal(got)
	}
	entries := List_Entries(ctx, NewList("x", "y"))
	if *entries.Items[1] != (ListEntry[string]{Index: 1, Value: "y"}) {
		t.Fatal(entries.Items[1])
	}
	if got := List_Concat(ctx, ints(1), ints(2)).Items; !reflect.DeepEqual(got, []int64{1, 2}) {
		t.Fatal(got)
	}
	if got := List_ToSet(ctx, nil, l).Len(); got != 3 {
		t.Fatal(got)
	}
}

func TestListFindReturnsVisitedValueAfterMutation(t *testing.T) {
	ctx := RootExecution()
	l := ints(1, 2, 3)
	got := List_Find(ctx, l, func(ctx *Execution, v int64) bool {
		if v == 1 {
			List_Set(ctx, l, 1, 20)
		}
		return v == 20
	})
	if got != Some(int64(20)) {
		t.Fatalf("find = %v", got)
	}
}

func TestListCallbackTraversalUsesCapturedHeader(t *testing.T) {
	ctx := RootExecution()
	l := ints(1, 2, 3)
	var seen []int64
	List_ForEach(ctx, l, func(ctx *Execution, v int64) Unit {
		seen = append(seen, v)
		if v == 1 {
			List_Append(ctx, l, 4)
			List_Pop(ctx, l)
			List_Pop(ctx, l)
		}
		return Unit{}
	})
	if !reflect.DeepEqual(seen, []int64{1, 2, 3}) {
		t.Fatalf("seen = %v", seen)
	}
}

func TestListSortedIsStableAndFaultsPropagate(t *testing.T) {
	ctx := RootExecution()
	type pair struct{ k, order int64 }
	l := NewList(pair{2, 0}, pair{1, 1}, pair{2, 2}, pair{1, 3}, pair{0, 4})
	got := List_Sorted(ctx, l, func(_ *Execution, a, b pair) int64 { return a.k - b.k })
	want := []pair{{0, 4}, {1, 1}, {1, 3}, {2, 0}, {2, 2}}
	if !reflect.DeepEqual(got.Items, want) {
		t.Fatalf("sorted = %v", got.Items)
	}
	if l.Items[0] != (pair{2, 0}) {
		t.Fatal("receiver changed")
	}
	fault(t, "boom", func() {
		List_Sorted(ctx, ints(3, 2, 1), func(*Execution, int64, int64) int64 { Raise("boom"); return 0 })
	})
}

func TestListReverse(t *testing.T) {
	ctx := RootExecution()
	l := ints(1, 2, 3)
	r := List_Reversed(ctx, l)
	if !reflect.DeepEqual(r.Items, []int64{3, 2, 1}) || !reflect.DeepEqual(l.Items, []int64{1, 2, 3}) {
		t.Fatal(r.Items, l.Items)
	}
	if List_ReverseInPlace(ctx, l) != l || l.Items[0] != 3 {
		t.Fatal("in place")
	}
}

func TestCollectionsFilledAndRange(t *testing.T) {
	ctx := RootExecution()
	if r := Collections_Filled(ctx, "x", 2, None[int64]()); r.Failed || !reflect.DeepEqual(r.Val.Items, []string{"x", "x"}) {
		t.Fatal(r)
	}
	if r := Collections_Filled(ctx, 0, -1, None[int64]()); r.Err != (CollectionError_InvalidInput{}) {
		t.Fatal(r)
	}
	if r := Collections_Filled(ctx, 0, 3, Some(int64(2))); r.Err != (CollectionError_LimitExceeded{}) {
		t.Fatal(r)
	}
	if r := Collections_Filled(ctx, 0, nativeMaxItems+1, None[int64]()); r.Err != (CollectionError_LimitExceeded{}) {
		t.Fatal(r)
	}
	cases := []struct {
		start, end, step int64
		max              Option[int64]
		want             []int64
		err              CollectionError
	}{
		{0, 5, 2, None[int64](), []int64{0, 2, 4}, nil},
		{5, 0, -2, None[int64](), []int64{5, 3, 1}, nil},
		{5, 0, 1, None[int64](), nil, nil},
		{0, 5, 0, None[int64](), nil, CollectionError_InvalidInput{}},
		{0, 5, 1, Some(int64(-1)), nil, CollectionError_InvalidInput{}},
		{0, 5, 1, Some(int64(4)), nil, CollectionError_LimitExceeded{}},
		{0, 5, 1, Some(int64(5)), []int64{0, 1, 2, 3, 4}, nil},
		{math.MinInt64, math.MaxInt64, 1, None[int64](), nil, CollectionError_LimitExceeded{}},
		{math.MaxInt64 - 1, math.MaxInt64, 5, None[int64](), []int64{math.MaxInt64 - 1}, nil},
	}
	for _, c := range cases {
		r := Collections_Range(ctx, c.start, c.end, c.step, c.max)
		if c.err != nil {
			if !r.Failed || r.Err != c.err {
				t.Errorf("%+v = %v", c, r)
			}
			continue
		}
		if r.Failed || len(r.Val.Items) != len(c.want) || (len(c.want) > 0 && !reflect.DeepEqual(r.Val.Items, c.want)) {
			t.Errorf("%+v = %v", c, r)
		}
	}
}

func TestMapOperations(t *testing.T) {
	ctx := RootExecution()
	m := MapOf(nil, []Entry[string, int64]{{"a", 1}, {"b", 2}, {"a", 3}})
	if Map_Length(ctx, m) != 2 || Map_GetOr(ctx, m, "a", 0) != 3 || Map_GetOr(ctx, m, "z", 9) != 9 {
		t.Fatal("literal")
	}
	if keys := Map_Keys(ctx, m).Items; !reflect.DeepEqual(keys, []string{"a", "b"}) {
		t.Fatal(keys)
	}
	Map_Add(ctx, m, "c", 4)
	Map_Remove(ctx, m, "a")
	Map_Add(ctx, m, "a", 5)
	if keys := Map_Keys(ctx, m).Items; !reflect.DeepEqual(keys, []string{"b", "c", "a"}) {
		t.Fatal(keys)
	}
	Map_AddDefault(ctx, m, "b", 100)
	Map_AddDefaultFrom(ctx, m, "d", func(_ *Execution, k string) int64 { return int64(len(k)) })
	Map_AddDefaultFrom(ctx, m, "c", func(*Execution, string) int64 { t.Fatal("must not create"); return 0 })
	if v := Map_Values(ctx, m).Items; !reflect.DeepEqual(v, []int64{2, 4, 5, 1}) {
		t.Fatal(v)
	}
	big := Map_Filter(ctx, m, func(_ *Execution, _ string, v int64) bool { return v > 2 })
	if k := Map_Keys(ctx, big).Items; !reflect.DeepEqual(k, []string{"c", "a"}) {
		t.Fatal(k)
	}
	doubled := Map_Map(ctx, m, func(_ *Execution, _ string, v int64) int64 { return v * 2 })
	if Map_Get(ctx, doubled, "c") != Some(int64(8)) || Map_Get(ctx, doubled, "q").Some {
		t.Fatal("map")
	}
	collapsed := Map_MapKeys(ctx, nil, m, func(_ *Execution, k string, _ int64) int { return len(k) })
	if collapsed.Len() != 1 {
		t.Fatal(collapsed.Len())
	}
	if v, _ := collapsed.Lookup(1); v != 1 {
		t.Fatalf("last value wins, got %d", v)
	}
	found := Map_Find(ctx, m, func(_ *Execution, _ string, v int64) bool { return v > 1 })
	if !found.Some || found.Val.Key != "b" {
		t.Fatal(found)
	}
	found.Val.Value = 77
	if Map_GetOr(ctx, m, "b", 0) != 2 {
		t.Fatal("entry records must not alias map storage")
	}
	if last := Map_FindLast(ctx, m, func(_ *Execution, _ string, v int64) bool { return v > 1 }); last.Val.Key != "a" {
		t.Fatal(last)
	}
	if !Map_Some(ctx, m, func(_ *Execution, k string, _ int64) bool { return k == "d" }) || Map_Every(ctx, m, func(_ *Execution, _ string, v int64) bool { return v > 1 }) {
		t.Fatal("some/every")
	}
	fold := Map_Fold(ctx, m, "", func(_ *Execution, a string, k string, _ int64) string { return a + k })
	foldRight := Map_FoldRight(ctx, m, "", func(_ *Execution, a string, k string, _ int64) string { return a + k })
	if fold != "bcad" || foldRight != "dacb" {
		t.Fatal(fold, foldRight)
	}
	clone := Map_Clone(ctx, m)
	Map_Merge(ctx, clone, MapOf(nil, []Entry[string, int64]{{"b", 0}, {"z", 26}}))
	if Map_GetOr(ctx, m, "b", -1) != 2 || Map_GetOr(ctx, clone, "b", -1) != 0 || Map_Length(ctx, clone) != 5 {
		t.Fatal("clone/merge")
	}
	if Map_Clear(ctx, clone) != clone || !Map_IsEmpty(ctx, clone) {
		t.Fatal("clear")
	}
	entries := Map_Entries(ctx, m)
	if len(entries.Items) != 4 || *entries.Items[0] != (MapEntry[string, int64]{"b", 2}) {
		t.Fatal(entries.Items)
	}
	round := Collections_MapFromEntries(ctx, nil, entries)
	if !MapEqual(ctx, m, round, eqInt) {
		t.Fatal("round trip")
	}
}

func TestMapSnapshotIsStableAcrossMutation(t *testing.T) {
	m := MapOf(nil, []Entry[int64, int64]{{1, 10}, {2, 20}, {3, 30}})
	var seen []int64
	for _, e := range m.Snapshot() {
		seen = append(seen, e.Value)
		m.Delete(2)
		m.Put(1, 11)
		m.Put(9, 90)
	}
	if !reflect.DeepEqual(seen, []int64{10, 20, 30}) {
		t.Fatal(seen)
	}
}

func TestMapManyDeletesKeepOrder(t *testing.T) {
	m := NewMap[int64, int64]()
	for i := int64(0); i < 200; i++ {
		m.Put(i, i)
	}
	for i := int64(0); i < 200; i++ {
		if i%5 != 0 {
			m.Delete(i)
		}
	}
	snap := m.Snapshot()
	if len(snap) != 40 || snap[0].Key != 0 || snap[39].Key != 195 {
		t.Fatal(len(snap))
	}
	if v, ok := m.Lookup(195); !ok || v != 195 {
		t.Fatal("lookup after compaction")
	}
}

func TestSetOperations(t *testing.T) {
	ctx := RootExecution()
	a, b := NewSet(1, 2, 3), NewSet(3, 4)
	check := func(name string, s *Set[int], want ...int) {
		t.Helper()
		if got := s.Snapshot(); !reflect.DeepEqual(got, want) {
			t.Errorf("%s = %v, want %v", name, got, want)
		}
	}
	check("union", Set_Union(ctx, a, b), 1, 2, 3, 4)
	check("intersection", Set_Intersection(ctx, a, b), 3)
	check("difference", Set_Difference(ctx, a, b), 1, 2)
	check("symmetric", Set_SymmetricDifference(ctx, a, b), 1, 2, 4)
	check("a unchanged", a, 1, 2, 3)
	if !Set_IsSubsetOf(ctx, NewSet(1), a) || Set_IsSubsetOf(ctx, b, a) || !Set_IsSupersetOf(ctx, a, NewSet(1, 2)) || !Set_IsDisjointFrom(ctx, NewSet(1), b) || Set_IsDisjointFrom(ctx, a, b) {
		t.Fatal("relations")
	}
	Set_Add(ctx, a, 2)
	Set_Add(ctx, a, 0)
	Set_Remove(ctx, a, 1)
	check("add/remove", a, 2, 3, 0)
	check("map", Set_Map(ctx, nil, a, func(_ *Execution, v int) int { return v / 2 }), 1, 0)
	check("filter", Set_Filter(ctx, a, func(_ *Execution, v int) bool { return v > 0 }), 2, 3)
	if Set_Find(ctx, a, func(_ *Execution, v int) bool { return v > 1 }) != Some(2) || Set_FindLast(ctx, a, func(_ *Execution, v int) bool { return v > 1 }) != Some(3) {
		t.Fatal("find")
	}
	if got := Set_Fold(ctx, a, "", func(_ *Execution, s string, v int) string { return s + FormatInt(int64(v)) }); got != "230" {
		t.Fatal(got)
	}
	if got := Set_FoldRight(ctx, a, "", func(_ *Execution, s string, v int) string { return s + FormatInt(int64(v)) }); got != "032" {
		t.Fatal(got)
	}
	if e := Set_Entries(ctx, NewSet("x")); !reflect.DeepEqual(e.Items[0].Items, []string{"x", "x"}) {
		t.Fatal(e.Items[0])
	}
	if !Set_Some(ctx, a, func(_ *Execution, v int) bool { return v == 0 }) || Set_Every(ctx, a, func(_ *Execution, v int) bool { return v > 0 }) {
		t.Fatal("some/every")
	}
	if Set_Clear(ctx, a) != a || !Set_IsEmpty(ctx, a) {
		t.Fatal("clear")
	}
}

func TestKeyMatchingIsGoEquality(t *testing.T) {
	type point struct{ x, y int64 }
	m := NewMap[point, string]()
	m.Put(point{1, 2}, "a")
	if v, ok := m.Lookup(point{1, 2}); !ok || v != "a" {
		t.Fatal("scalar-only struct keys match by value")
	}
	type ref struct{ n int64 }
	r1, r2 := &ref{1}, &ref{1}
	s := NewSet(r1)
	if !s.Has(r1) || s.Has(r2) {
		t.Fatal("pointer keys match by identity")
	}
	f := NewSet(math.NaN())
	if f.Has(math.NaN()) {
		t.Fatal("NaN never matches")
	}
}

func TestBuilders(t *testing.T) {
	ctx := RootExecution()
	lb := NewListBuilder[int64]()
	ListBuilder_Append(ctx, lb, 1)
	ListBuilder_Append(ctx, lb, 2)
	l := ListBuilder_Freeze(ctx, lb)
	if !reflect.DeepEqual(l.Items, []int64{1, 2}) || ListBuilder_Freeze(ctx, lb) != l {
		t.Fatal(l.Items)
	}
	fault(t, "builder is sealed", func() { ListBuilder_Append(ctx, lb, 3) })
	mb := NewMapBuilder[string, int64](nil)
	MapBuilder_Add(ctx, mb, "a", 1)
	MapBuilder_Add(ctx, mb, "b", 2)
	MapBuilder_Add(ctx, mb, "a", 3)
	m := MapBuilder_Freeze(ctx, mb)
	if !reflect.DeepEqual(Map_Keys(ctx, m).Items, []string{"a", "b"}) || Map_GetOr(ctx, m, "a", 0) != 3 {
		t.Fatal("map builder")
	}
	fault(t, "builder is sealed", func() { MapBuilder_Add(ctx, mb, "c", 1) })
	sb := NewSetBuilder[int64](nil)
	SetBuilder_Add(ctx, sb, 2)
	SetBuilder_Add(ctx, sb, 2)
	if s := SetBuilder_Freeze(ctx, sb); s.Len() != 1 {
		t.Fatal("set builder")
	}
	fault(t, "builder is sealed", func() { SetBuilder_Add(ctx, sb, 1) })
}

func TestEquality(t *testing.T) {
	ctx := RootExecution()
	if !ListEqual(ctx, ints(1, 2), ints(1, 2), eqInt) || ListEqual(ctx, ints(1, 2), ints(1, 3), eqInt) || ListEqual(ctx, ints(1), ints(1, 2), eqInt) {
		t.Fatal("list")
	}
	nested := func(a, b *List[*List[int64]]) bool {
		return ListEqual(ctx, a, b, func(ctx *Execution, x, y *List[int64]) bool { return ListEqual(ctx, x, y, eqInt) })
	}
	if !nested(NewList(ints(1)), NewList(ints(1))) || nested(NewList(ints(1)), NewList(ints(2))) {
		t.Fatal("nested")
	}
	if !SetEqual(ctx, NewSet(1, 2), NewSet(2, 1)) || SetEqual(ctx, NewSet(1), NewSet(2)) || SetEqual(ctx, NewSet(1), NewSet(1, 2)) {
		t.Fatal("set")
	}
	x := MapOf(nil, []Entry[string, int64]{{"a", 1}, {"b", 2}})
	y := MapOf(nil, []Entry[string, int64]{{"b", 2}, {"a", 1}})
	z := MapOf(nil, []Entry[string, int64]{{"a", 1}, {"b", 3}})
	if !MapEqual(ctx, x, y, eqInt) || MapEqual(ctx, x, z, eqInt) || MapEqual(ctx, x, NewMap[string, int64](), eqInt) {
		t.Fatal("map")
	}
}

func TestEqualityCapturesBothHeadersBeforeCallbacks(t *testing.T) {
	ctx := RootExecution()
	a, b := ints(1, 2, 3), ints(1, 2, 3)
	calls := 0
	got := ListEqual(ctx, a, b, func(ctx *Execution, x, y int64) bool {
		calls++
		List_Append(ctx, a, 4)
		List_Pop(ctx, b)
		return x == y
	})
	if !got || calls != 3 {
		t.Fatalf("equal = %v after %d calls", got, calls)
	}
}

func TestFormat(t *testing.T) {
	str := func(v int64) string { return FormatInt(v) }
	if got := FormatList(ints(1, 2, 3), str); got != "[1, 2, 3]" {
		t.Fatal(got)
	}
	if got := FormatList(ints(), str); got != "[]" {
		t.Fatal(got)
	}
	if got := FormatSet(NewSet[int64](2, 1), str); got != "Set(2, 1)" {
		t.Fatal(got)
	}
	m := MapOf(nil, []Entry[string, int64]{{"a", 1}, {"b", 2}})
	if got := FormatMap(m, func(s string) string { return s }, str); got != "Map(a: 1, b: 2)" {
		t.Fatal(got)
	}
	if got := FormatMap(NewMap[string, int64](), func(s string) string { return s }, str); got != "Map()" {
		t.Fatal(got)
	}
}

func TestOptional(t *testing.T) {
	ctx := RootExecution()
	some, none := Some(int64(4)), None[int64]()
	if !Optional_IsSome(ctx, some) || Optional_IsSome(ctx, none) || !Optional_IsNone(ctx, none) {
		t.Fatal("is")
	}
	if Optional_Unwrap(ctx, some) != 4 || Optional_UnwrapOr(ctx, none, 7) != 7 || Optional_UnwrapOr(ctx, some, 7) != 4 {
		t.Fatal("unwrap")
	}
	fault(t, "called Optional.unwrap() on none; check is_some first", func() { Optional_Unwrap(ctx, none) })
	create := func(*Execution) int64 { return 9 }
	if Optional_UnwrapOrElse(ctx, none, create) != 9 || Optional_UnwrapOrElse(ctx, some, func(*Execution) int64 { t.Fatal("eager"); return 0 }) != 4 {
		t.Fatal("unwrap_or_else")
	}
	double := func(_ *Execution, v int64) int64 { return v * 2 }
	if Optional_Map(ctx, some, double) != Some(int64(8)) || Optional_Map(ctx, none, double).Some {
		t.Fatal("map")
	}
	chain := func(_ *Execution, v int64) Option[string] { return Some(FormatInt(v)) }
	if Optional_AndThen(ctx, some, chain) != Some("4") || Optional_AndThen(ctx, none, chain).Some {
		t.Fatal("and_then")
	}
	if Optional_OrElse(ctx, none, func(*Execution) Option[int64] { return Some(int64(1)) }) != Some(int64(1)) || Optional_OrElse(ctx, some, nil) != some {
		t.Fatal("or_else")
	}
	if r := Optional_OkOr(ctx, some, Some("why")); r.Failed || r.Val != 4 {
		t.Fatal(r)
	}
	if r := Optional_OkOr(ctx, none, Some("why")); !r.Failed || r.Err != "why" {
		t.Fatal(r)
	}
	if r := Optional_OkOr(ctx, none, None[MissingValue]()); !r.Failed {
		t.Fatal(r)
	} else if _, ok := r.Err.(MissingValue_Missing); !ok {
		t.Fatalf("err = %T", r.Err)
	}
	fault(t, "called Optional.ok_or() without a cause for an error type other than MissingValue", func() { Optional_OkOr(ctx, none, None[string]()) })
	if r := Optional_OkOrElse(ctx, none, func(*Execution) string { return "made" }); r.Err != "made" {
		t.Fatal(r)
	}
	if r := Optional_OkOrElse(ctx, some, func(*Execution) string { t.Fatal("eager"); return "" }); r.Val != 4 {
		t.Fatal(r)
	}
}

func TestResult(t *testing.T) {
	ctx := RootExecution()
	ok, bad := Ok[int64, string](4), Fail[int64, string]("e")
	if !Result_IsOk(ctx, ok) || Result_IsOk(ctx, bad) || !Result_IsError(ctx, bad) {
		t.Fatal("is")
	}
	if Result_Unwrap(ctx, ok) != 4 || Result_UnwrapError(ctx, bad) != "e" || Result_UnwrapOr(ctx, bad, 1) != 1 || Result_UnwrapOr(ctx, ok, 1) != 4 {
		t.Fatal("unwrap")
	}
	fault(t, "called Result.unwrap() on error; check is_ok first", func() { Result_Unwrap(ctx, bad) })
	fault(t, "called Result.unwrap_error() on ok; check is_error first", func() { Result_UnwrapError(ctx, ok) })
	if Result_UnwrapOrElse(ctx, bad, func(_ *Execution, e string) int64 { return int64(len(e)) + 10 }) != 11 {
		t.Fatal("unwrap_or_else")
	}
	double := func(_ *Execution, v int64) int64 { return v * 2 }
	if r := Result_Map(ctx, ok, double); r.Val != 8 || r.Failed {
		t.Fatal(r)
	}
	if r := Result_Map(ctx, bad, double); !r.Failed || r.Err != "e" {
		t.Fatal(r)
	}
	if r := Result_AndThen(ctx, ok, func(_ *Execution, v int64) Result[string, string] { return Fail[string, string]("no") }); r.Err != "no" {
		t.Fatal(r)
	}
	if Result_ToOptional(ctx, ok) != Some(int64(4)) || Result_ToOptional(ctx, bad).Some {
		t.Fatal("to_optional")
	}
	mapped := ResultMapError(bad, func(e string) int { return len(e) })
	if !mapped.Failed || mapped.Err != 1 || ResultMapError(ok, func(e string) int { return 0 }).Val != 4 {
		t.Fatal("map_error")
	}
}

func TestCollectionErrorMessages(t *testing.T) {
	ctx := RootExecution()
	for e, want := range map[CollectionError]string{
		CollectionError_InvalidInput{}:  "collection: invalid input",
		CollectionError_LimitExceeded{}: "collection: limit exceeded",
		CollectionError_OutOfRange{}:    "collection: value out of range",
	} {
		if got := Errors_Message_CollectionError(ctx, e); got != want {
			t.Errorf("%T = %q", e, got)
		}
	}
}

func TestCollectionLoopsHonorCancellation(t *testing.T) {
	ctx := RootExecution()
	cancelCtx, cancel := context.WithCancel(context.Background())
	ctx.Context = cancelCtx
	cancel()
	defer func() {
		if _, ok := recover().(cancelled); !ok {
			t.Fatal("want cancellation")
		}
	}()
	List_Count(ctx, ints(1, 2, 3), func(*Execution, int64) bool { return true })
}

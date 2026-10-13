package msruntime

import (
	"math"
	"sort"
)

// ListSorted creates separate shallow backing. Primitive comparator entrypoints
// avoid reboxing every comparison; arbitrary callables retain ordinary Invoke.
func ListSorted(ctx *Execution, receiver, compare Value) *List {
	list := receiver.(*List)
	compare = listComparator(compare)
	if compare == nil {
		out := list.CopySlice(0, list.Len())
		return ListSortInPlace(ctx, out, nil)
	}
	fn := compare.(Function)
	if list.kind == listInt && fn.IntCompare != nil && ordinaryCompareLabels(fn) {
		out := list.CopySlice(0, list.Len())
		sort.SliceStable(out.ints, func(i, j int) bool {
			CheckCancelled(ctx)
			return fn.IntCompare(ctx, out.ints[i], out.ints[j]) < 0
		})
		return out
	}
	if list.kind == listFloat && fn.FloatCompare != nil && ordinaryCompareLabels(fn) {
		out := list.CopySlice(0, list.Len())
		sort.SliceStable(out.floats, func(i, j int) bool {
			CheckCancelled(ctx)
			return fn.FloatCompare(ctx, out.floats[i], out.floats[j]) < 0
		})
		return out
	}
	// Box once per element for a callback that only accepts Values. Boxing
	// inside Less regressed the earlier storage-only experiment by 2.26x.
	// This temporary array never becomes a persistent List mirror.
	out := list.Boxed()
	sort.SliceStable(out, func(i, j int) bool {
		CheckCancelled(ctx)
		return Invoke(ctx, compare, []Argument{{"left", out[i]}, {"right", out[j]}}).(int64) < 0
	})
	return NewList(list.Type, out)
}

// ListSortInPlace captures a Go header, so swaps affect shared backing while a
// comparator's append never extends the sort or switches its captured array.
func ListSortInPlace(ctx *Execution, receiver, compare Value) *List {
	list := receiver.(*List)
	compare = listComparator(compare)
	natural := list.kind
	if natural == listBoxed {
		natural = newList(list.Type).kind
	}
	if compare == nil && natural == listBoxed {
		Panic("List sorting without compare requires Int, Float, Bool, or String elements; provide compare for other elements")
	}
	captured := *list
	sort.Stable(&listSorter{ctx: ctx, list: captured, compare: compare, natural: natural})
	return list
}
func listComparator(value Value) Value {
	if optional, ok := value.(Alternative); ok {
		if optional.Tag == "none" {
			return nil
		}
		if optional.Tag == "some" {
			return optional.Fields[0]
		}
	}
	return value
}

type listSorter struct {
	ctx     *Execution
	list    List
	compare Value
	natural uint8
}

func (s *listSorter) Len() int      { return s.list.Len() }
func (s *listSorter) Swap(i, j int) { s.list.swap(i, j) }
func (s *listSorter) Less(i, j int) bool {
	CheckCancelled(s.ctx)
	if s.compare == nil {
		switch s.natural {
		case listInt:
			return s.list.Capture().Int(i) < s.list.Capture().Int(j)
		case listFloat:
			return naturalFloatLess(s.list.Capture().Float(i), s.list.Capture().Float(j))
		case listBool:
			return !s.list.Capture().Bool(i) && s.list.Capture().Bool(j)
		case listString:
			return s.list.Capture().String(i) < s.list.Capture().String(j)
		}
	}
	fn := s.compare.(Function)
	if s.list.kind == listInt && fn.IntCompare != nil && ordinaryCompareLabels(fn) {
		return fn.IntCompare(s.ctx, s.list.ints[i], s.list.ints[j]) < 0
	}
	if s.list.kind == listFloat && fn.FloatCompare != nil && ordinaryCompareLabels(fn) {
		return fn.FloatCompare(s.ctx, s.list.floats[i], s.list.floats[j]) < 0
	}
	return Invoke(s.ctx, fn, []Argument{{"left", s.list.Get(i)}, {"right", s.list.Get(j)}}).(int64) < 0
}
func naturalFloatLess(left, right float64) bool {
	return left < right || math.IsNaN(left) && !math.IsNaN(right)
}

func ordinaryCompareLabels(fn Function) bool {
	return len(fn.Labels) == 2 && fn.Labels[0] == "left" && fn.Labels[1] == "right"
}

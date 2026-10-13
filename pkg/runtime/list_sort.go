package msruntime

import "sort"

// ListSorted creates separate shallow backing. Primitive comparator entrypoints
// avoid reboxing every comparison; arbitrary callables retain ordinary Invoke.
func ListSorted(ctx *Execution, receiver, compare Value) *List {
	list := receiver.(*List)
	fn := compare.(Function)
	if list.kind == listInt && fn.IntCompare != nil {
		out := list.CopySlice(0, list.Len())
		sort.SliceStable(out.ints, func(i, j int) bool {
			CheckCancelled(ctx)
			return fn.IntCompare(ctx, out.ints[i], out.ints[j]) < 0
		})
		return out
	}
	if list.kind == listFloat && fn.FloatCompare != nil {
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

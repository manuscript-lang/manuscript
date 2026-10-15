package rt

// Map operations. Keys match as Go compares them (see Map).

// Map_Clone returns a shallow copy.
func Map_Clone[K comparable, V any](_ *Execution, m *Map[K, V]) *Map[K, V] {
	out := NewMap[K, V]()
	for _, e := range m.Snapshot() {
		out.Put(e.Key, e.Value)
	}
	return out
}

// Map_IsEmpty reports whether the map has no entries.
func Map_IsEmpty[K comparable, V any](_ *Execution, m *Map[K, V]) bool { return m.Len() == 0 }

// Map_Length is the entry count.
func Map_Length[K comparable, V any](_ *Execution, m *Map[K, V]) int64 { return int64(m.Len()) }

// Map_Filter returns a new map of the entries the predicate accepts.
func Map_Filter[K comparable, V any](ctx *Execution, m *Map[K, V], keep func(*Execution, K, V) bool) *Map[K, V] {
	out, tick := NewMap[K, V](), uint32(0)
	CheckCancelled(ctx)
	for _, e := range m.Snapshot() {
		Poll(ctx, &tick)
		if keep(ctx, e.Key, e.Value) {
			out.Put(e.Key, e.Value)
		}
	}
	return out
}

// Map_Map transforms each value, keeping the keys.
func Map_Map[K comparable, V, W any](ctx *Execution, m *Map[K, V], transform func(*Execution, K, V) W) *Map[K, W] {
	out, tick := NewMap[K, W](), uint32(0)
	CheckCancelled(ctx)
	for _, e := range m.Snapshot() {
		Poll(ctx, &tick)
		out.Put(e.Key, transform(ctx, e.Key, e.Value))
	}
	return out
}

// Map_MapKeys transforms each key; a repeated new key keeps its first
// position and its last value.
func Map_MapKeys[K comparable, V any, W comparable](ctx *Execution, m *Map[K, V], transform func(*Execution, K, V) W) *Map[W, V] {
	out, tick := NewMap[W, V](), uint32(0)
	CheckCancelled(ctx)
	for _, e := range m.Snapshot() {
		Poll(ctx, &tick)
		out.Put(transform(ctx, e.Key, e.Value), e.Value)
	}
	return out
}

// Map_GetOr returns the value under key, or fallback.
func Map_GetOr[K comparable, V any](_ *Execution, m *Map[K, V], key K, fallback V) V {
	if v, ok := m.Lookup(key); ok {
		return v
	}
	return fallback
}

// Map_Fold folds the entries in insertion order.
func Map_Fold[K comparable, V, A any](ctx *Execution, m *Map[K, V], initial A, step func(*Execution, A, K, V) A) A {
	tick := uint32(0)
	CheckCancelled(ctx)
	for _, e := range m.Snapshot() {
		Poll(ctx, &tick)
		initial = step(ctx, initial, e.Key, e.Value)
	}
	return initial
}

// Map_FoldRight folds the entries in reverse insertion order.
func Map_FoldRight[K comparable, V, A any](ctx *Execution, m *Map[K, V], initial A, step func(*Execution, A, K, V) A) A {
	tick, entries := uint32(0), m.Snapshot()
	CheckCancelled(ctx)
	for i := len(entries) - 1; i >= 0; i-- {
		Poll(ctx, &tick)
		initial = step(ctx, initial, entries[i].Key, entries[i].Value)
	}
	return initial
}

func mapFind[K comparable, V any](ctx *Execution, m *Map[K, V], pred func(*Execution, K, V) bool, reverse bool) *MapEntry[K, V] {
	entries, tick := m.Snapshot(), uint32(0)
	CheckCancelled(ctx)
	if reverse {
		for i := len(entries) - 1; i >= 0; i-- {
			Poll(ctx, &tick)
			if pred(ctx, entries[i].Key, entries[i].Value) {
				return entries[i]
			}
		}
		return nil
	}
	for _, e := range entries {
		Poll(ctx, &tick)
		if pred(ctx, e.Key, e.Value) {
			return e
		}
	}
	return nil
}

// foundEntry gives the caller a fresh record: entries are records the
// program may mutate, and the map's own entries must stay untouched.
func foundEntry[K comparable, V any](e *MapEntry[K, V]) Option[*MapEntry[K, V]] {
	if e == nil {
		return Option[*MapEntry[K, V]]{}
	}
	return Some(&MapEntry[K, V]{Key: e.Key, Value: e.Value})
}

// Map_Find returns the first entry the predicate accepts.
func Map_Find[K comparable, V any](ctx *Execution, m *Map[K, V], pred func(*Execution, K, V) bool) Option[*MapEntry[K, V]] {
	return foundEntry(mapFind(ctx, m, pred, false))
}

// Map_FindLast returns the last entry the predicate accepts.
func Map_FindLast[K comparable, V any](ctx *Execution, m *Map[K, V], pred func(*Execution, K, V) bool) Option[*MapEntry[K, V]] {
	return foundEntry(mapFind(ctx, m, pred, true))
}

// Map_Some reports whether the predicate accepts any entry.
func Map_Some[K comparable, V any](ctx *Execution, m *Map[K, V], pred func(*Execution, K, V) bool) bool {
	return mapFind(ctx, m, pred, false) != nil
}

// Map_Every reports whether the predicate accepts every entry.
func Map_Every[K comparable, V any](ctx *Execution, m *Map[K, V], pred func(*Execution, K, V) bool) bool {
	return mapFind(ctx, m, func(ctx *Execution, k K, v V) bool { return !pred(ctx, k, v) }, false) == nil
}

// Map_AddDefault stores value only when key is absent.
func Map_AddDefault[K comparable, V any](_ *Execution, m *Map[K, V], key K, value V) *Map[K, V] {
	if _, ok := m.Lookup(key); !ok {
		m.Put(key, value)
	}
	return m
}

// Map_AddDefaultFrom stores create(key) only when key is absent.
func Map_AddDefaultFrom[K comparable, V any](ctx *Execution, m *Map[K, V], key K, create func(*Execution, K) V) *Map[K, V] {
	if _, ok := m.Lookup(key); ok {
		return m
	}
	m.Put(key, create(ctx, key))
	return m
}

// Map_Clear removes every entry.
func Map_Clear[K comparable, V any](_ *Execution, m *Map[K, V]) *Map[K, V] {
	m.Clear()
	return m
}

// Map_Keys lists the keys in insertion order.
func Map_Keys[K comparable, V any](_ *Execution, m *Map[K, V]) *List[K] {
	entries := m.Snapshot()
	out := make([]K, len(entries))
	for i, e := range entries {
		out[i] = e.Key
	}
	return &List[K]{Items: out}
}

// Map_Values lists the values in insertion order.
func Map_Values[K comparable, V any](_ *Execution, m *Map[K, V]) *List[V] {
	entries := m.Snapshot()
	out := make([]V, len(entries))
	for i, e := range entries {
		out[i] = e.Value
	}
	return &List[V]{Items: out}
}

// Map_Entries lists fresh entry records in insertion order.
func Map_Entries[K comparable, V any](_ *Execution, m *Map[K, V]) *List[*MapEntry[K, V]] {
	entries := m.Snapshot()
	out := make([]*MapEntry[K, V], len(entries))
	for i, e := range entries {
		out[i] = &MapEntry[K, V]{Key: e.Key, Value: e.Value}
	}
	return &List[*MapEntry[K, V]]{Items: out}
}

// Map_Merge stores other's entries into m, in place.
func Map_Merge[K comparable, V any](ctx *Execution, m, other *Map[K, V]) *Map[K, V] {
	tick := uint32(0)
	CheckCancelled(ctx)
	for _, e := range other.Snapshot() {
		Poll(ctx, &tick)
		m.Put(e.Key, e.Value)
	}
	return m
}

// Map_ForEach calls operation on each entry in insertion order.
func Map_ForEach[K comparable, V any](ctx *Execution, m *Map[K, V], operation func(*Execution, K, V) Unit) Unit {
	tick := uint32(0)
	CheckCancelled(ctx)
	for _, e := range m.Snapshot() {
		Poll(ctx, &tick)
		operation(ctx, e.Key, e.Value)
	}
	return Unit{}
}

// Map_Contains reports whether key is present.
func Map_Contains[K comparable, V any](_ *Execution, m *Map[K, V], key K) bool {
	_, ok := m.Lookup(key)
	return ok
}

// Map_Get returns the value under key, or none.
func Map_Get[K comparable, V any](_ *Execution, m *Map[K, V], key K) Option[V] {
	if v, ok := m.Lookup(key); ok {
		return Some(v)
	}
	return Option[V]{}
}

// Map_Add stores value under key, in place.
func Map_Add[K comparable, V any](_ *Execution, m *Map[K, V], key K, value V) *Map[K, V] {
	m.Put(key, value)
	return m
}

// Map_Remove deletes key, in place.
func Map_Remove[K comparable, V any](_ *Execution, m *Map[K, V], key K) *Map[K, V] {
	m.Delete(key)
	return m
}

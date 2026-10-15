package rt

// Entry is a map literal element.
type Entry[K comparable, V any] struct {
	Key   K
	Value V
}

// Map is Manuscript's insertion-ordered mutable map. Keys match as Go
// compares them: scalar values and scalar-only records by value, everything
// else by reference.
type Map[K comparable, V any] struct {
	index   map[K]int
	entries []*MapEntry[K, V] // nil marks a removed entry until compaction
	live    int
}

// NewMap returns an empty map.
func NewMap[K comparable, V any]() *Map[K, V] { return &Map[K, V]{index: map[K]int{}} }

// MapOf returns a map holding entries; a repeated key keeps its first
// position and its last value.
func MapOf[K comparable, V any](entries []Entry[K, V]) *Map[K, V] {
	m := NewMap[K, V]()
	for _, e := range entries {
		m.Put(e.Key, e.Value)
	}
	return m
}

// Len is the number of entries.
func (m *Map[K, V]) Len() int { return m.live }

// Lookup returns the value stored under key.
func (m *Map[K, V]) Lookup(key K) (V, bool) {
	if i, ok := m.index[key]; ok {
		return m.entries[i].Value, true
	}
	var zero V
	return zero, false
}

// Put stores value under key, appending a new key.
func (m *Map[K, V]) Put(key K, value V) {
	if i, ok := m.index[key]; ok {
		m.entries[i] = &MapEntry[K, V]{Key: key, Value: value}
		return
	}
	m.index[key] = len(m.entries)
	m.entries = append(m.entries, &MapEntry[K, V]{Key: key, Value: value})
	m.live++
}

// Delete removes key and reports whether it was present.
func (m *Map[K, V]) Delete(key K) bool {
	i, ok := m.index[key]
	if !ok {
		return false
	}
	delete(m.index, key)
	m.entries[i] = nil
	m.live--
	if len(m.entries) > 32 && m.live < len(m.entries)/2 {
		m.compact()
	}
	return true
}

func (m *Map[K, V]) compact() {
	kept := m.entries[:0]
	for _, e := range m.entries {
		if e != nil {
			m.index[e.Key] = len(kept)
			kept = append(kept, e)
		}
	}
	clear(m.entries[len(kept):])
	m.entries = kept
}

// Clear removes every entry.
func (m *Map[K, V]) Clear() {
	m.index = map[K]int{}
	m.entries = nil
	m.live = 0
}

// Snapshot returns the live entries in insertion order. A loop over a map
// ranges over it, so the loop sees the map as it was when the loop began.
func (m *Map[K, V]) Snapshot() []*MapEntry[K, V] {
	out := make([]*MapEntry[K, V], 0, m.live)
	for _, e := range m.entries {
		if e != nil {
			out = append(out, e)
		}
	}
	return out
}

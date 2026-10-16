package msruntime

// Entry is a map literal element.
type Entry[K comparable, V any] struct {
	Key   K
	Value V
}

// Map is Manuscript's insertion-ordered mutable map.
//
// Keys match as the program's Hashable and Equal rules say. Types whose Go
// equality is their Manuscript equality (scalars, strings, handles, which
// match by identity) use Go map lookup directly. Types with structural or
// explicit equality carry Keys, which project a key to a comparable form or
// supply a hash and an equality. Float NaN never matches itself. The same rule
// applies to Set elements.
type Map[K comparable, V any] struct {
	keys    *Keys[K]
	index   map[K]int
	project map[any]int
	buckets map[int][]int
	entries []*MapEntry[K, V] // nil marks a removed entry until compaction
	live    int
}

// NewMap returns an empty map whose keys match by Go equality.
func NewMap[K comparable, V any]() *Map[K, V] { return NewMapWith[K, V](nil) }

// NewMapWith returns an empty map whose keys match as keys say; nil keys mean
// Go equality.
func NewMapWith[K comparable, V any](keys *Keys[K]) *Map[K, V] {
	m := &Map[K, V]{keys: keys}
	m.reset()
	return m
}

func (m *Map[K, V]) reset() {
	switch {
	case m.keys == nil:
		m.index = map[K]int{}
	case m.keys.Project != nil:
		m.project = map[any]int{}
	default:
		m.buckets = map[int][]int{}
	}
}

// Keys is how the map matches keys.
func (m *Map[K, V]) Keys() *Keys[K] { return m.keys }

// MapOf returns a map holding entries; a repeated key keeps its first
// position and its last value.
func MapOf[K comparable, V any](keys *Keys[K], entries []Entry[K, V]) *Map[K, V] {
	m := NewMapWith[K, V](keys)
	for _, e := range entries {
		m.Put(e.Key, e.Value)
	}
	return m
}

// Len is the number of entries.
func (m *Map[K, V]) Len() int { return m.live }

func (m *Map[K, V]) find(key K) (int, bool) {
	switch {
	case m.keys == nil:
		i, ok := m.index[key]
		return i, ok
	case m.keys.Project != nil:
		i, ok := m.project[m.keys.Project(key)]
		return i, ok
	}
	for _, i := range m.buckets[m.keys.Hash(key)] {
		if m.keys.Equal(m.entries[i].Key, key) {
			return i, true
		}
	}
	return 0, false
}

func (m *Map[K, V]) bind(key K, i int) {
	switch {
	case m.keys == nil:
		m.index[key] = i
	case m.keys.Project != nil:
		m.project[m.keys.Project(key)] = i
	default:
		h := m.keys.Hash(key)
		m.buckets[h] = append(m.buckets[h], i)
	}
}

func (m *Map[K, V]) unbind(key K, i int) {
	switch {
	case m.keys == nil:
		delete(m.index, key)
	case m.keys.Project != nil:
		delete(m.project, m.keys.Project(key))
	default:
		h := m.keys.Hash(key)
		chain := m.buckets[h]
		for j, at := range chain {
			if at == i {
				chain = append(chain[:j:j], chain[j+1:]...)
				break
			}
		}
		if len(chain) == 0 {
			delete(m.buckets, h)
		} else {
			m.buckets[h] = chain
		}
	}
}

// Lookup returns the value stored under key.
func (m *Map[K, V]) Lookup(key K) (V, bool) {
	if i, ok := m.find(key); ok {
		return m.entries[i].Value, true
	}
	var zero V
	return zero, false
}

// Put stores value under key, appending a new key.
func (m *Map[K, V]) Put(key K, value V) {
	if i, ok := m.find(key); ok {
		// Replacement retains the original key and insertion position. The
		// entry is replaced, not mutated, so a Snapshot taken earlier is stable.
		m.entries[i] = &MapEntry[K, V]{Key: m.entries[i].Key, Value: value}
		return
	}
	m.bind(key, len(m.entries))
	m.entries = append(m.entries, &MapEntry[K, V]{Key: key, Value: value})
	m.live++
}

// Delete removes key and reports whether it was present.
func (m *Map[K, V]) Delete(key K) bool {
	i, ok := m.find(key)
	if !ok {
		return false
	}
	m.unbind(m.entries[i].Key, i)
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
			kept = append(kept, e)
		}
	}
	clear(m.entries[len(kept):])
	m.entries = kept
	m.reset()
	for i, e := range m.entries {
		m.bind(e.Key, i)
	}
}

// Clear removes every entry.
func (m *Map[K, V]) Clear() {
	m.reset()
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

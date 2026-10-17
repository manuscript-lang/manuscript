package msruntime

import "sync/atomic"

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
	entries []mapSlot[K, V] // a slot with live false marks a removed entry until compaction
	live    int
	writing uint32 // 1 while a task inserts, deletes or clears; detects unsynchronized sharing
}

// mapSlot stores an entry by value, so adding or replacing one allocates
// nothing; Snapshot copies the live slots, which keeps earlier snapshots stable.
type mapSlot[K comparable, V any] struct {
	Key   K
	Value V
	live  bool
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
		if m.index == nil {
			m.index = map[K]int{}
		}
		clear(m.index)
	case m.keys.Project != nil:
		if m.project == nil {
			m.project = map[any]int{}
		}
		clear(m.project)
	default:
		if m.buckets == nil {
			m.buckets = map[int][]int{}
		}
		clear(m.buckets)
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

// Maps are not synchronized: tasks sharing one must lock a Synchronized around
// every access. Go's own map would end the process with an unrecoverable
// "concurrent map writes" trace, so overlapping use is caught first and
// raised as an ordinary fault. Detection covers accesses that overlap an
// insert, delete or clear; it is a diagnostic, not a guarantee.
const concurrentMapMessage = "concurrent access to a Map or Set from several tasks; share it through a Synchronized and hold its lock around every read and write"

func (m *Map[K, V]) beginWrite() {
	if !atomic.CompareAndSwapUint32(&m.writing, 0, 1) {
		Raise(concurrentMapMessage)
	}
}

func (m *Map[K, V]) endWrite() { atomic.StoreUint32(&m.writing, 0) }

func (m *Map[K, V]) find(key K) (int, bool) {
	if atomic.LoadUint32(&m.writing) != 0 {
		Raise(concurrentMapMessage)
	}
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
		// Replacement retains the original key and insertion position. A
		// Snapshot holds copies, so it is unaffected.
		m.entries[i].Value = value
		return
	}
	m.beginWrite()
	m.bind(key, len(m.entries))
	m.entries = append(m.entries, mapSlot[K, V]{Key: key, Value: value, live: true})
	m.live++
	m.endWrite()
}

// Delete removes key and reports whether it was present.
func (m *Map[K, V]) Delete(key K) bool {
	i, ok := m.find(key)
	if !ok {
		return false
	}
	m.beginWrite()
	m.unbind(m.entries[i].Key, i)
	m.entries[i] = mapSlot[K, V]{}
	m.live--
	if len(m.entries) > 32 && m.live < len(m.entries)/2 {
		m.compact()
	}
	m.endWrite()
	return true
}

func (m *Map[K, V]) compact() {
	kept := m.entries[:0]
	for _, e := range m.entries {
		if e.live {
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
	m.beginWrite()
	m.reset()
	m.entries = nil
	m.live = 0
	m.endWrite()
}

// Snapshot returns the live entries in insertion order. A loop over a map
// ranges over it, so the loop sees the map as it was when the loop began.
func (m *Map[K, V]) Snapshot() []*MapEntry[K, V] {
	copies := m.Copies()
	out := make([]*MapEntry[K, V], len(copies))
	for i := range copies {
		out[i] = &copies[i]
	}
	return out
}

// Copies returns the live entries in insertion order as values the caller
// owns, in one allocation. A for loop over a map ranges over them, so it sees
// the map as it was when the loop began.
func (m *Map[K, V]) Copies() []MapEntry[K, V] {
	out := make([]MapEntry[K, V], 0, m.live)
	for _, e := range m.entries {
		if e.live {
			out = append(out, MapEntry[K, V]{Key: e.Key, Value: e.Value})
		}
	}
	return out
}
